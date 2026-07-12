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

  /// Notified whenever a brand-new queue starts (for the saved-queues archive).
  void Function(List<Track>)? onNewQueue;

  Timer? _tick;

  PlayerService(this.bridge) {
    // One tick per second of *playing* time drives listen counting, the sleep
    // timer, and periodic position saving.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_player.playing) return;
      final t = currentTrack;
      if (t != null) history?.onPositionTick(t);
      _sleepOnTick();
      _transitionFadeOnTick();
      if (++_posTicks % 5 == 0) _savePosition();
    });
    // Chained play-next resets once playback moves to a new track; when
    // transition fades are on, each new track opens with a short fade-in.
    _player.currentIndexStream.listen((_) {
      _lastInsert = null;
      final fadeSec = settings?.transitionFadeSec ?? 0;
      if (fadeSec > 0 && _player.playing) {
        final seq = ++_rampSeq;
        _player.setVolume(0.15);
        _ramp(0.15, _baseVolume, (fadeSec * 350).clamp(700, 2500), seq);
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

  /// Where the audio actually comes from: an explicit URI (local file,
  /// MediaStore content://, YouTube stream) or the bridge's /stream endpoint.
  AudioSource _sourceFor(Track t) {
    final url = t.sourceUri ?? bridge.streamUrl(t.filePath);
    return AudioSource.uri(
      Uri.parse(url),
      tag: MediaItem(
        id: t.id,
        title: t.title,
        artist: t.artist,
        album: t.album,
        duration: t.duration > 0
            ? Duration(milliseconds: (t.duration * 1000).round())
            : null,
        artUri: _artUriFor(t),
      ),
    );
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

  Future<void> playQueue(List<Track> tracks, int startIndex,
      {String? collectionId, Duration? startPosition}) async {
    _queue = List.of(tracks);
    currentCollectionId = collectionId;
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
  Future<void> playShuffled(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    _queue = List.of(tracks);
    queueRevision.value++;
    _saveQueueSoon();
    onNewQueue?.call(_queue);
    await _player.setAudioSources(_queue.map(_sourceFor).toList());
    await _player.setShuffleModeEnabled(true);
    await _player.shuffle();
    _player.play();
  }

  int? _lastInsert; // where the last play-next landed, for chaining

  /// Insert right after the current track ("play next"). Successive calls
  /// chain: A, B, C inserted while a track plays will play in A→B→C order
  /// instead of C→B→A.
  Future<void> playNext(Track t) async {
    if (_queue.isEmpty) return playQueue([t], 0);
    final current = _player.currentIndex ?? -1;
    var at = (_lastInsert != null && _lastInsert! > current)
        ? _lastInsert! + 1
        : current + 1;
    at = at.clamp(0, _queue.length);
    _queue.insert(at, t);
    _lastInsert = at;
    queueRevision.value++;
    _saveQueueSoon();
    await _player.insertAudioSource(at, _sourceFor(t));
  }

  /// Append to the end of the queue.
  Future<void> addToQueue(Track t) async {
    if (_queue.isEmpty) return playQueue([t], 0);
    _queue.add(t);
    queueRevision.value++;
    _saveQueueSoon();
    await _player.addAudioSource(_sourceFor(t));
  }

  /// Removes and returns the track so callers can offer undo.
  Future<Track?> removeFromQueue(int index) async {
    if (index < 0 || index >= _queue.length || _queue.length <= 1) return null;
    final removed = _queue.removeAt(index);
    queueRevision.value++;
    _saveQueueSoon();
    await _player.removeAudioSourceAt(index);
    return removed;
  }

  /// Undo helper — puts a removed track back at its original slot.
  Future<void> insertAt(int index, Track t) async {
    if (_queue.isEmpty) return playQueue([t], 0);
    final at = index.clamp(0, _queue.length);
    _queue.insert(at, t);
    queueRevision.value++;
    _saveQueueSoon();
    await _player.insertAudioSource(at, _sourceFor(t));
  }

  /// Bulk removals, Namida-style. Returns how many rows went away.
  Future<int> removeDuplicates() => _removeWhere((i, t) {
        final firstIdx = _queue.indexWhere((x) => x.key == t.key);
        return firstIdx != i && i != (_player.currentIndex ?? -1);
      });

  Future<int> removeAllPrevious() async {
    final current = _player.currentIndex ?? 0;
    return _removeWhere((i, _) => i < current);
  }

  Future<int> removeAllNext() async {
    final current = _player.currentIndex ?? 0;
    return _removeWhere((i, _) => i > current);
  }

  Future<int> _removeWhere(bool Function(int, Track) test) async {
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
    if (removed > 0) {
      queueRevision.value++;
      _saveQueueSoon();
    }
    return removed;
  }

  Future<void> moveInQueue(int from, int to) async {
    if (from < 0 || from >= _queue.length) return;
    to = to.clamp(0, _queue.length - 1);
    if (from == to) return;
    final t = _queue.removeAt(from);
    _queue.insert(to, t);
    queueRevision.value++;
    _saveQueueSoon();
    await _player.moveAudioSource(from, to);
  }

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
      // Unreachable sources (bridge offline) or corrupt rows — start empty.
    }
  }

  Future<void> _saveQueueSoon() async {
    final db = _db;
    if (db == null || _queueSavePending) return;
    _queueSavePending = true;
    await Future.delayed(const Duration(seconds: 1));
    _queueSavePending = false;
    try {
      // Serialize off the UI isolate — a 2000-track queue is megabytes of
      // jsonEncode work. (Perf audit finding.)
      final encoded = await compute(encodeTracksJson, List.of(_queue));
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

  /// Play/pause with a short volume ramp (when enabled) instead of hard cuts.
  Future<void> togglePlay() async {
    final s = settings;
    final fade = s?.playPauseFade ?? false;
    final ms = s?.fadeMs ?? 300;
    if (!fade) {
      return _player.playing ? _player.pause() : _player.play();
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
  Future<void> next() => _player.seekToNext();
  Future<void> previous() => _player.seekToPrevious();
  Future<void> seek(Duration d) => _player.seek(d);
  Future<void> skipTo(int index) => _player.seek(Duration.zero, index: index);

  /// Namida-style previous: restart the track if it's already played a bit,
  /// only jump back when near the start.
  Future<void> previousSmart() {
    if (_player.position.inSeconds > 5) return _player.seek(Duration.zero);
    return _player.seekToPrevious();
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

class SleepTimerState {
  final DateTime? endsAt; // minutes mode
  final int? tracksLeft; // tracks mode
  const SleepTimerState({required this.endsAt, required this.tracksLeft});
}
