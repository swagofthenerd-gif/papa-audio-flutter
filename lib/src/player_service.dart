import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:sqflite/sqflite.dart';

import 'bridge.dart';
import 'db.dart';
import 'history.dart';
import 'local_library.dart';
import 'models.dart';
import 'settings.dart';
import 'yt/yt_service.dart';

/// Native gapless playback via just_audio + a background/lock-screen handler.
/// This is the layer that gives the "buttery" feel — audio runs on the platform
/// side, not in a JS bridge. Also owns the queue (with in-place edits), the
/// sleep timer, playback speed/pitch, the equalizer pipeline, and feeds listen
/// ticks to [HistoryService].
class PlayerService {
  final Bridge bridge;
  final AndroidEqualizer equalizer = AndroidEqualizer();
  final AndroidLoudnessEnhancer loudness = AndroidLoudnessEnhancer();
  late final AudioPlayer _player = AudioPlayer(
    audioPipeline: AudioPipeline(androidAudioEffects: [loudness, equalizer]),
  );
  List<Track> _queue = [];

  /// Queue edits (add/remove/reorder) bump this so UI lists rebuild.
  final ValueNotifier<int> queueRevision = ValueNotifier(0);

  HistoryService? history;
  SettingsService? settings;

  /// On-device YouTube stream resolution. When set, `yt:` tracks without a
  /// sourceUri play through a lazy resolving source instead of the PC bridge.
  YtStreamResolver? ytResolver;
  int? _errorRetryIndex; // queue index we've already retried after a stream error

  /// Notified whenever a brand-new queue starts (for the saved-queues archive).
  void Function(List<Track>)? onNewQueue;

  /// Fired when playback moves to a new track — used for the ListenBrainz
  /// "now playing" ping.
  void Function(Track)? onTrackStart;

  Timer? _tick;

  PlayerService(this.bridge) {
    // One tick per second of *playing* time drives listen counting, the sleep
    // timer, and periodic position saving.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_player.playing) return;
      final t = currentTrack;
      if (t != null) {
        history?.onPositionTick(t,
            positionSec: _player.position.inMilliseconds / 1000.0);
      }
      _sleepOnTick();
      _transitionFadeOnTick();
      if (++_posTicks % 5 == 0) _savePosition();
    });
    // Optional queue-end behavior: instead of stopping on the last track,
    // return to the top of the queue, paused and ready to play again.
    _player.processingStateStream.listen((st) async {
      if (st == ProcessingState.completed &&
          _player.loopMode == LoopMode.off &&
          (settings?.queueEndRestart ?? false) &&
          _queue.isNotEmpty) {
        await _player.pause();
        await _player.seek(Duration.zero, index: 0);
        _restoreAfterFadeIfIdle();
      }
    });
    // Chained play-next resets once playback moves to a new track; when
    // transition fades are on, each new track opens with a short fade-in.
    // A dead stream (region-locked/removed YouTube track, expired URL) must
    // never halt an hours-long session. Most failures are expired URLs, so for
    // a YouTube track try ONE fresh-URL retry of the same track before giving
    // up and skipping to the next entry.
    _player.playbackEventStream.listen((_) {}, onError: (Object e, _) async {
      final i = _player.currentIndex;
      if (i == null || i < 0 || i >= _queue.length) return;
      final t = _queue[i];
      final isYt = t.sourceUri == null && t.id.startsWith('yt:');
      try {
        if (isYt && _errorRetryIndex != i) {
          _errorRetryIndex = i; // one retry per track occurrence
          ytResolver?.invalidate(t.id.substring(3));
          await _player.seek(Duration.zero, index: i); // re-request fresh URL
          if (_player.playing) _player.play();
          return;
        }
        if (i + 1 < _queue.length) {
          await _player.seek(Duration.zero, index: i + 1);
          if (_player.playing) _player.play();
        }
      } catch (_) {}
    });
    _player.currentIndexStream.listen((i) {
      _lastInsert = null;
      if (_errorRetryIndex != i) _errorRetryIndex = null; // moved on — re-arm retry
      _prefetchUpcomingYt(i);
      final started = currentTrack;
      if (started != null) onTrackStart?.call(started);
      if (_pendingNextKey != null &&
          i != null &&
          i >= 0 &&
          i < _queue.length &&
          _queue[i].key == _pendingNextKey) {
        _pendingNextKey = null; // the play-next target is now playing
      }
      final fadeSec = settings?.transitionFadeSec ?? 0;
      if (fadeSec > 0 && _player.playing) {
        final seq = ++_rampSeq;
        _player.setVolume(0.15);
        _ramp(0.15, _baseVolume, (fadeSec * 350).clamp(700, 2500), seq);
      } else {
        // A tail fade may have lowered the volume with no fade-in coming
        // (fades disabled mid-track, or paused at the boundary) — restore.
        _restoreAfterFadeIfIdle();
      }
    });
  }

  /// Apply persisted audio settings once they're loaded.
  Future<void> applySettings(SettingsService s) async {
    settings = s;
    try {
      await _player.setSkipSilenceEnabled(s.skipSilence);
    } catch (_) {}
  }

  AudioPlayer get player => _player;
  List<Track> get queue => _queue;

  Stream<PlayerState> get playerState => _player.playerStateStream;
  Stream<Duration> get position => _player.positionStream;
  Stream<Duration> get bufferedPosition => _player.bufferedPositionStream;
  Stream<Duration?> get duration => _player.durationStream;
  Stream<int?> get currentIndex => _player.currentIndexStream;
  Stream<bool> get shuffleEnabled => _player.shuffleModeEnabledStream;
  Stream<LoopMode> get loopMode => _player.loopModeStream;
  Stream<double> get speedStream => _player.speedStream;

  Track? get currentTrack {
    final i = _player.currentIndex;
    if (i == null || i < 0 || i >= _queue.length) return null;
    return _queue[i];
  }

  /// The track that would audibly play on next()/previous() — shuffle- and
  /// loop-aware (just_audio computes these over its effective order). The
  /// artwork carousel uses them so the visual neighbor always matches the
  /// audible one.
  Track? get effectiveNextTrack => trackAt(_player.nextIndex);
  Track? get effectivePreviousTrack => trackAt(_player.previousIndex);

  Track? trackAt(int? i) =>
      (i == null || i < 0 || i >= _queue.length) ? null : _queue[i];

  /// Where the audio actually comes from: an explicit URI (local file,
  /// MediaStore content://, YouTube stream) or the bridge's /stream endpoint.
  AudioSource _sourceFor(Track t) {
    final tag = MediaItem(
      id: t.id,
      title: t.title,
      artist: t.artist,
      album: t.album,
      duration: t.duration > 0
          ? Duration(milliseconds: (t.duration * 1000).round())
          : null,
      artUri: _artUriFor(t),
    );
    // On-device YouTube: resolve the stream lazily at play time, so enqueuing
    // a 30-track mix costs nothing up front.
    final resolver = ytResolver;
    if (resolver != null && t.sourceUri == null && t.id.startsWith('yt:')) {
      return YtLazyAudioSource(t.id.substring(3), resolver, tag: tag);
    }
    final url = t.sourceUri ?? bridge.streamUrl(t.filePath);
    return AudioSource.uri(Uri.parse(url), tag: tag);
  }

  /// Warm stream URLs for the next queue entries so YT track changes are
  /// gapless-feeling. Called on every index change.
  void _prefetchUpcomingYt(int? index) {
    final resolver = ytResolver;
    if (resolver == null || index == null) return;
    final ids = <String>[];
    for (var i = index; i < _queue.length && ids.length < 3; i++) {
      final t = _queue[i];
      if (t.sourceUri == null && t.id.startsWith('yt:')) {
        ids.add(t.id.substring(3));
      }
    }
    resolver.prefetch(ids);
  }

  /// Lock-screen artwork URI. `localart://` is an in-app convention, so it maps
  /// to the MediaStore albumart content URI the notification can resolve.
  Uri? _artUriFor(Track t) {
    final a = t.artUri;
    if (a != null) {
      final local = RegExp(r'^localart://\d+/(\d+)$').firstMatch(a);
      if (local != null) {
        return LocalLibrary.notificationArtUri(int.parse(local.group(1)!));
      }
      return Uri.tryParse(a);
    }
    final url = bridge.artUrl(t.artPath, width: 512);
    return url != null ? Uri.parse(url) : null;
  }

  // ── Queue ───────────────────────────────────────────────────────────────────

  /// The collection (album/playlist/folder…) the current queue came from, so
  /// its listening position can be remembered and resumed later.
  String? currentCollectionId;

  /// All queue mutations run through this chain. A bulk edit awaits hundreds
  /// of sequential player ops; a user action landing mid-flight would compute
  /// its index against the mutated [_queue] while the player still holds the
  /// old source list, desyncing the two for the rest of the session.
  Future<void> _queueOps = Future.value();
  Future<T> _queueOp<T>(Future<T> Function() op) {
    final run = _queueOps.then((_) => op());
    _queueOps = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// Bookkeeping shared by structural queue edits: once edited, the queue no
  /// longer mirrors the collection it was created from, so its resume point
  /// must stop tracking (or the saved index would point at the wrong track).
  void _queueEdited() {
    currentCollectionId = null;
    queueRevision.value++;
    _saveQueueSoon();
  }

  Future<void> playQueue(List<Track> tracks, int startIndex,
          {String? collectionId, Duration? startPosition}) =>
      _queueOp(() => _playQueueLocked(tracks, startIndex,
          collectionId: collectionId, startPosition: startPosition));

  Future<void> _playQueueLocked(List<Track> tracks, int startIndex,
      {String? collectionId, Duration? startPosition}) async {
    _queue = List.of(tracks);
    currentCollectionId = collectionId;
    _pendingNextKey = null;
    queueRevision.value++;
    _saveQueueSoon();
    onNewQueue?.call(_queue);
    await _player.setAudioSources(
      _queue.map(_sourceFor).toList(),
      initialIndex: startIndex,
      initialPosition: startPosition,
    );
    _player.play();
  }

  /// Shuffle-play a whole list: random start + shuffle mode on.
  Future<void> playShuffled(List<Track> tracks) => _queueOp(() async {
        if (tracks.isEmpty) return;
        _queue = List.of(tracks);
        // Not a collection queue — leaving the previous id in place would let
        // the 5s position saver overwrite that collection's resume point with
        // positions from this shuffled queue.
        currentCollectionId = null;
        _pendingNextKey = null;
        queueRevision.value++;
        _saveQueueSoon();
        onNewQueue?.call(_queue);
        await _player.setAudioSources(_queue.map(_sourceFor).toList());
        await _player.setShuffleModeEnabled(true);
        await _player.shuffle();
        _player.play();
      });

  int? _lastInsert; // where the last play-next landed, for chaining

  /// In shuffle mode the platform's shuffle order won't visit a freshly
  /// inserted sequence slot next — [next] compensates by seeking straight to
  /// this track. Natural advance still follows the platform's shuffle order.
  String? _pendingNextKey;

  /// Insert right after the current track ("play next"). Successive calls
  /// chain: A, B, C inserted while a track plays will play in A→B→C order
  /// instead of C→B→A.
  Future<void> playNext(Track t) => _queueOp(() async {
        if (_queue.isEmpty) return _playQueueLocked([t], 0);
        final current = _player.currentIndex ?? -1;
        var at = (_lastInsert != null && _lastInsert! > current)
            ? _lastInsert! + 1
            : current + 1;
        at = at.clamp(0, _queue.length);
        _queue.insert(at, t);
        _lastInsert = at;
        if (_player.shuffleModeEnabled) _pendingNextKey ??= t.key;
        _queueEdited();
        await _player.insertAudioSource(at, _sourceFor(t));
      });

  /// Append to the end of the queue.
  Future<void> addToQueue(Track t) => _queueOp(() async {
        if (_queue.isEmpty) return _playQueueLocked([t], 0);
        _queue.add(t);
        _queueEdited();
        await _player.addAudioSource(_sourceFor(t));
      });

  /// Removes and returns the track so callers can offer undo.
  Future<Track?> removeFromQueue(int index) => _queueOp(() async {
        if (index < 0 || index >= _queue.length || _queue.length <= 1) {
          return null;
        }
        final removed = _queue.removeAt(index);
        _queueEdited();
        await _player.removeAudioSourceAt(index);
        return removed;
      });

  /// Undo helper — puts a removed track back at its original slot.
  Future<void> insertAt(int index, Track t) => _queueOp(() async {
        if (_queue.isEmpty) return _playQueueLocked([t], 0);
        final at = index.clamp(0, _queue.length);
        _queue.insert(at, t);
        _queueEdited();
        await _player.insertAudioSource(at, _sourceFor(t));
      });

  /// Bulk removals, Namida-style. Returns how many rows went away.
  Future<int> removeDuplicates() => _removeWhere((i, t) {
        final firstIdx = _queue.indexWhere((x) => x.key == t.key);
        return firstIdx != i && i != (_player.currentIndex ?? -1);
      });

  Future<int> removeAllPrevious() =>
      _removeWhere((i, _) => i < (_player.currentIndex ?? 0));

  Future<int> removeAllNext() =>
      _removeWhere((i, _) => i > (_player.currentIndex ?? 0));

  Future<int> removeAllExceptCurrent() =>
      _removeWhere((i, _) => i != (_player.currentIndex ?? 0));

  Future<int> _removeWhere(bool Function(int, Track) test) =>
      _queueOp(() async {
        var removed = 0;
        // Walk backwards so earlier indices stay valid while removing.
        for (var i = _queue.length - 1; i >= 0; i--) {
          if (_queue.length <= 1) break;
          if (test(i, _queue[i])) {
            _queue.removeAt(i);
            await _player.removeAudioSourceAt(i);
            removed++;
          }
        }
        if (removed > 0) _queueEdited();
        return removed;
      });

  Future<void> moveInQueue(int from, int to) => _queueOp(() async {
        if (from < 0 || from >= _queue.length) return;
        to = to.clamp(0, _queue.length - 1);
        if (from == to) return;
        final t = _queue.removeAt(from);
        _queue.insert(to, t);
        _queueEdited();
        await _player.moveAudioSource(from, to);
      });

  // ── Queue persistence (Namida-style "restore last session") ────────────────

  AppDatabase? _db;
  bool _queueSavePending = false;
  int _posTicks = 0;

  /// Load the last session's queue paused at its saved position.
  Future<void> initPersistence(AppDatabase db) async {
    _db = db;
    try {
      final rows = await db.db.query('queue_tracks', orderBy: 'pos ASC');
      if (rows.isEmpty) return;
      final tracks = [
        for (final r in rows)
          Track.fromJson(
              jsonDecode(r['track_json'] as String) as Map<String, dynamic>)
      ];
      final index = int.tryParse(await db.getKv('queue_index') ?? '') ?? 0;
      final posMs =
          int.tryParse(await db.getKv('queue_position_ms') ?? '') ?? 0;
      _queue = tracks;
      queueRevision.value++;
      await _player.setAudioSources(
        tracks.map(_sourceFor).toList(),
        initialIndex: index.clamp(0, tracks.length - 1),
        initialPosition: Duration(milliseconds: posMs),
      );
      // Deliberately not playing — the queue sits ready, like a native player.
    } catch (_) {
      // Unreachable sources (bridge offline) or corrupt rows: the player has
      // no sources, so drop the in-memory queue too — otherwise the UI shows a
      // full queue whose rows all skipTo an empty player.
      _queue = [];
      queueRevision.value++;
    }
  }

  int _queueSaveSeq = 0; // newest save wins even if an older encode finishes late

  Future<void> _saveQueueSoon() async {
    final db = _db;
    if (db == null || _queueSavePending) return;
    _queueSavePending = true;
    await Future.delayed(const Duration(seconds: 1));
    _queueSavePending = false;
    final seq = ++_queueSaveSeq;
    try {
      // Serialize off the UI isolate — a 2000-track queue is megabytes of
      // jsonEncode work. (Perf audit finding.)
      final encoded = await compute(encodeTracksJson, List.of(_queue));
      // A newer save started while this one was encoding — its snapshot is
      // fresher, so drop this stale write instead of racing it to the DB.
      if (seq != _queueSaveSeq) return;
      await db.db.transaction((txn) async {
        await txn.delete('queue_tracks');
        final batch = txn.batch();
        for (var i = 0; i < encoded.length; i++) {
          batch.insert('queue_tracks', {'pos': i, 'track_json': encoded[i]});
        }
        await batch.commit(noResult: true);
      });
    } catch (_) {}
    _savePosition();
  }

  void _savePosition() {
    final db = _db;
    if (db == null) return;
    try {
      final index = _player.currentIndex ?? 0;
      final posMs = _player.position.inMilliseconds;
      db.setKv('queue_index', '$index');
      db.setKv('queue_position_ms', '$posMs');
      final cid = currentCollectionId;
      if (cid != null) {
        db.db.insert(
            'collection_resume',
            {
              'collection_id': cid,
              'track_index': index,
              'position_ms': posMs,
              'track_title': currentTrack?.title,
              'updated_at': DateTime.now().millisecondsSinceEpoch,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    } catch (_) {}
  }

  /// The most recently resumed collections, newest first — powers the home
  /// "Jump back in" shelf. Rows whose position is essentially the very start
  /// are dropped (nothing meaningful to resume).
  Future<List<CollectionResume>> recentCollections({int limit = 10}) async {
    final db = _db;
    if (db == null) return const [];
    try {
      final rows = await db.db.query('collection_resume',
          orderBy: 'updated_at DESC', limit: limit * 2);
      final out = <CollectionResume>[];
      for (final r in rows) {
        final index = r['track_index'] as int;
        final posMs = r['position_ms'] as int;
        if (index == 0 && posMs < 3000) continue;
        out.add(CollectionResume(
          collectionId: r['collection_id'] as String,
          index: index,
          positionMs: posMs,
          trackTitle: r['track_title'] as String?,
          updatedAt: r['updated_at'] as int,
        ));
        if (out.length >= limit) break;
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  // ── Video-toggle coordination ──────────────────────────────────────────────

  /// Pause audio so the video overlay can take over, returning the position
  /// (seconds) the video should start from.
  Future<double> suspendForVideo() async {
    final at = _player.position.inMilliseconds / 1000.0;
    await _player.pause();
    return at;
  }

  /// Resume audio at [sec] after the video overlay closes.
  Future<void> resumeFromVideo(double sec) async {
    try {
      await _player.seek(Duration(milliseconds: (sec * 1000).round()));
    } catch (_) {}
    _restoreAfterFadeIfIdle();
    _player.play();
  }

  /// Saved listening position for a collection, if any.
  Future<ResumePoint?> resumeFor(String collectionId) async {
    final db = _db;
    if (db == null) return null;
    try {
      final rows = await db.db.query('collection_resume',
          where: 'collection_id = ?', whereArgs: [collectionId]);
      if (rows.isEmpty) return null;
      return ResumePoint(
        index: rows.first['track_index'] as int,
        positionMs: rows.first['position_ms'] as int,
        trackTitle: rows.first['track_title'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Transport ───────────────────────────────────────────────────────────────

  /// The volume the player should sit at when no fade is in flight. Fades
  /// always resolve back to this — interrupting them can never ratchet the
  /// real volume down (that bug plays everything silently).
  static const _baseVolume = 1.0;
  int _rampSeq = 0; // newer ramps cancel older ones

  /// True while the video overlay owns playback; audio must stay paused so the
  /// two engines never play at once. Transport play/pause routes to the video.
  bool videoActive = false;
  void Function()? onVideoPlayPause;

  /// Play/pause with a short volume ramp (when enabled) instead of hard cuts.
  Future<void> togglePlay() async {
    // Video mode: the transport controls the video, never the (paused) audio,
    // so tapping play can't stack a second audio stream on top of the video.
    if (videoActive) {
      onVideoPlayPause?.call();
      return;
    }
    final s = settings;
    final fade = s?.playPauseFade ?? false;
    final ms = s?.fadeMs ?? 300;
    if (!fade) {
      if (_player.playing) {
        await _player.pause();
      } else {
        // A tail fade may have left the volume down; resume at full volume.
        _restoreAfterFadeIfIdle();
        _player.play();
      }
      return;
    }
    final seq = ++_rampSeq;
    if (_player.playing) {
      await _ramp(_player.volume, 0, ms, seq);
      if (seq != _rampSeq) return; // a newer toggle took over
      await _player.pause();
      await _player.setVolume(_baseVolume);
    } else {
      await _player.setVolume(0);
      _player.play();
      await _ramp(0, _baseVolume, ms, seq);
      if (seq == _rampSeq) await _player.setVolume(_baseVolume);
    }
  }

  Future<void> _ramp(double from, double to, int ms, int seq) async {
    const steps = 8;
    for (var i = 1; i <= steps; i++) {
      if (seq != _rampSeq) return; // cancelled by a newer ramp
      await _player.setVolume(from + (to - from) * i / steps);
      await Future.delayed(Duration(milliseconds: ms ~/ steps));
    }
  }
  Future<void> next() async {
    final pending = _pendingNextKey;
    if (pending != null && _player.shuffleModeEnabled) {
      // A play-next insert is waiting; the shuffle order won't reach it next,
      // so jump straight there.
      final idx = _queue.indexWhere((t) => t.key == pending);
      _pendingNextKey = null;
      if (idx >= 0) {
        await _player.seek(Duration.zero, index: idx);
        _maybePlayOnSkip();
        return;
      }
    }
    await _player.seekToNext();
    _maybePlayOnSkip();
  }

  /// If a tail fade dropped the volume and no fade-in is going to restore it
  /// (playback paused/idle at a track boundary), bring it back to base.
  void _restoreAfterFadeIfIdle() {
    if (_player.volume < _baseVolume) {
      _rampSeq++; // cancel any in-flight ramp loop
      _player.setVolume(_baseVolume);
    }
  }

  Future<void> previous() async {
    await _player.seekToPrevious();
    _maybePlayOnSkip();
  }

  Future<void> seek(Duration d) => _player.seek(d);
  Future<void> skipTo(int index) => _player.seek(Duration.zero, index: index);

  /// Namida-style previous: restart the track if it's already played a bit,
  /// only jump back when near the start.
  Future<void> previousSmart() async {
    if (_player.position.inSeconds > 5) {
      await _player.seek(Duration.zero);
    } else {
      await _player.seekToPrevious();
    }
    _maybePlayOnSkip();
  }

  /// Optional: skipping while paused starts playback.
  void _maybePlayOnSkip() {
    if ((settings?.playOnSkip ?? false) && !_player.playing) togglePlay();
  }

  Future<void> toggleShuffle() async {
    final enable = !_player.shuffleModeEnabled;
    if (enable) await _player.shuffle(); // re-roll the order each time
    await _player.setShuffleModeEnabled(enable);
  }

  /// off → all → one → off
  Future<void> cycleRepeat() {
    const order = [LoopMode.off, LoopMode.all, LoopMode.one];
    final next = order[(order.indexOf(_player.loopMode) + 1) % order.length];
    return _player.setLoopMode(next);
  }

  Future<void> setSpeed(double speed) async {
    speed = speed.clamp(0.25, 3.0);
    await _player.setSpeed(speed);
    if (settings?.linkSpeedPitch ?? false) await _player.setPitch(speed);
  }

  double get speed => _player.speed;

  Future<void> setPitch(double pitch) => _player.setPitch(pitch.clamp(0.5, 2.0));
  double get pitch => _player.pitch;
  Stream<double> get pitchStream => _player.pitchStream;

  Future<void> setSkipSilence(bool on) => _player.setSkipSilenceEnabled(on);

  // ── Sleep timer ─────────────────────────────────────────────────────────────

  final ValueNotifier<SleepTimerState?> sleepTimer = ValueNotifier(null);
  int _sleepTracksLeft = 0;
  String? _sleepLastKey;

  /// [minutes] or [tracks] (whichever is set; minutes wins if both).
  void startSleepTimer({int? minutes, int? tracks}) {
    if (minutes != null) {
      sleepTimer.value = SleepTimerState(
          endsAt: DateTime.now().add(Duration(minutes: minutes)), tracksLeft: null);
    } else if (tracks != null) {
      _sleepTracksLeft = tracks;
      _sleepLastKey = currentTrack?.key;
      sleepTimer.value = SleepTimerState(endsAt: null, tracksLeft: tracks);
    }
  }

  void cancelSleepTimer() {
    sleepTimer.value = null;
    _sleepTracksLeft = 0;
    _sleepLastKey = null;
  }

  void _sleepOnTick() {
    final s = sleepTimer.value;
    if (s == null) return;
    if (s.endsAt != null) {
      if (!DateTime.now().isBefore(s.endsAt!)) {
        cancelSleepTimer();
        _fadeOutAndPause();
      }
      return;
    }
    // Track-count mode: detect track changes.
    final k = currentTrack?.key;
    if (k != null && k != _sleepLastKey) {
      _sleepLastKey = k;
      _sleepTracksLeft--;
      if (_sleepTracksLeft <= 0) {
        cancelSleepTimer();
        _fadeOutAndPause();
      } else {
        sleepTimer.value = SleepTimerState(endsAt: null, tracksLeft: _sleepTracksLeft);
      }
    }
  }

  /// Fade the tail of the current track when transition fades are enabled.
  /// The paired fade-in runs from the currentIndex listener; ExoPlayer's
  /// playlist advance is already gapless, so tail-fade + head-fade reads as a
  /// soft crossfade without a second player.
  void _transitionFadeOnTick() {
    final fadeSec = settings?.transitionFadeSec ?? 0;
    if (fadeSec <= 0 || _player.loopMode == LoopMode.one) return;
    final duration = _player.duration;
    if (duration == null || duration == Duration.zero) return;
    final remaining = duration - _player.position;
    if (remaining.inSeconds <= fadeSec && remaining.inSeconds >= 0) {
      // Don't fight an in-flight manual ramp (play/pause or sleep fade).
      final v = (remaining.inMilliseconds / (fadeSec * 1000))
          .clamp(0.15, 1.0)
          .toDouble();
      if (v < _player.volume) _player.setVolume(v);
    }
  }

  /// Gentle 3s fade instead of a hard stop.
  Future<void> _fadeOutAndPause() async {
    final seq = ++_rampSeq;
    for (var i = 9; i >= 0; i--) {
      if (seq != _rampSeq) return; // user toggled play — abandon the fade
      await _player.setVolume(_baseVolume * i / 10);
      await Future.delayed(const Duration(milliseconds: 300));
    }
    await _player.pause();
    await _player.setVolume(_baseVolume);
  }

  Future<void> dispose() async {
    _tick?.cancel();
    await _player.dispose();
  }
}

/// Isolate worker shared by queue persistence and the saved-queues archive.
List<String> encodeTracksJson(List<Track> tracks) =>
    [for (final t in tracks) jsonEncode(t.toJson())];

class ResumePoint {
  final int index;
  final int positionMs;
  final String? trackTitle;
  const ResumePoint(
      {required this.index, required this.positionMs, this.trackTitle});
}

/// A saved resume position for a collection (album/playlist/…), used by the
/// home "Jump back in" shelf.
class CollectionResume {
  final String collectionId;
  final int index;
  final int positionMs;
  final String? trackTitle;
  final int updatedAt;
  const CollectionResume({
    required this.collectionId,
    required this.index,
    required this.positionMs,
    this.trackTitle,
    required this.updatedAt,
  });
}

class SleepTimerState {
  final DateTime? endsAt; // minutes mode
  final int? tracksLeft; // tracks mode
  const SleepTimerState({required this.endsAt, required this.tracksLeft});
}
