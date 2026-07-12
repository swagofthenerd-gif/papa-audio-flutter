import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';

import 'bridge.dart';
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
  Timer? _tick;

  PlayerService(this.bridge) {
    // One tick per second of *playing* time drives listen counting, the sleep
    // timer, and periodic position saving.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_player.playing) return;
      final t = currentTrack;
      if (t != null) history?.onPositionTick(t);
      _sleepOnTick();
      if (++_posTicks % 5 == 0) _savePosition();
    });
    // Chained play-next resets once playback moves to a new track.
    _player.currentIndexStream.listen((_) => _lastInsert = null);
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

  Future<void> playQueue(List<Track> tracks, int startIndex) async {
    _queue = List.of(tracks);
    queueRevision.value++;
    _saveQueueSoon();
    await _player.setAudioSources(
      _queue.map(_sourceFor).toList(),
      initialIndex: startIndex,
    );
    _player.play();
  }

  /// Shuffle-play a whole list: random start + shuffle mode on.
  Future<void> playShuffled(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    _queue = List.of(tracks);
    queueRevision.value++;
    _saveQueueSoon();
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

  File? _queueFile;
  File? _posFile;
  bool _queueSavePending = false;
  int _posTicks = 0;

  /// Load the last session's queue paused at its saved position.
  Future<void> initPersistence() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      _queueFile = File('${docs.path}${Platform.pathSeparator}queue.json');
      _posFile = File('${docs.path}${Platform.pathSeparator}queue_pos.json');
      if (!await _queueFile!.exists()) return;
      // Large queues decode off the UI thread — startup stays smooth.
      final j = await compute(_decodeMap, await _queueFile!.readAsString());
      final tracks = ((j['tracks'] ?? []) as List)
          .map((t) => Track.fromJson(t as Map<String, dynamic>))
          .toList();
      if (tracks.isEmpty) return;
      var index = 0;
      var posMs = 0;
      try {
        if (await _posFile!.exists()) {
          final p = jsonDecode(await _posFile!.readAsString())
              as Map<String, dynamic>;
          index = (p['index'] as num?)?.toInt() ?? 0;
          posMs = (p['positionMs'] as num?)?.toInt() ?? 0;
        }
      } catch (_) {}
      _queue = tracks;
      queueRevision.value++;
      await _player.setAudioSources(
        tracks.map(_sourceFor).toList(),
        initialIndex: index.clamp(0, tracks.length - 1),
        initialPosition: Duration(milliseconds: posMs),
      );
      // Deliberately not playing — the queue sits ready, like a native player.
    } catch (_) {
      // Unreachable sources (bridge offline) or corrupt files — start empty.
    }
  }

  Future<void> _saveQueueSoon() async {
    final f = _queueFile;
    if (f == null || _queueSavePending) return;
    _queueSavePending = true;
    await Future.delayed(const Duration(seconds: 1));
    _queueSavePending = false;
    try {
      await f.writeAsString(
          jsonEncode({'tracks': _queue.map((t) => t.toJson()).toList()}));
    } catch (_) {}
    _savePosition();
  }

  void _savePosition() {
    final f = _posFile;
    if (f == null) return;
    try {
      f.writeAsString(jsonEncode({
        'index': _player.currentIndex ?? 0,
        'positionMs': _player.position.inMilliseconds,
      }));
    } catch (_) {}
  }

  // ── Transport ───────────────────────────────────────────────────────────────

  /// Play/pause with a short volume ramp (when enabled) instead of hard cuts.
  Future<void> togglePlay() async {
    final s = settings;
    final fade = s?.playPauseFade ?? false;
    final ms = s?.fadeMs ?? 300;
    if (!fade) {
      return _player.playing ? _player.pause() : _player.play();
    }
    final target = _player.volume <= 0 ? 1.0 : _player.volume;
    if (_player.playing) {
      await _ramp(target, 0, ms);
      await _player.pause();
      await _player.setVolume(target);
    } else {
      await _player.setVolume(0);
      _player.play();
      await _ramp(0, target, ms);
    }
  }

  Future<void> _ramp(double from, double to, int ms) async {
    const steps = 8;
    for (var i = 1; i <= steps; i++) {
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

  /// Gentle 3s fade instead of a hard stop.
  Future<void> _fadeOutAndPause() async {
    final v = _player.volume;
    for (var i = 9; i >= 0; i--) {
      await _player.setVolume(v * i / 10);
      await Future.delayed(const Duration(milliseconds: 300));
    }
    await _player.pause();
    await _player.setVolume(v);
  }

  Future<void> dispose() async {
    _tick?.cancel();
    await _player.dispose();
  }
}

Map<String, dynamic> _decodeMap(String raw) =>
    jsonDecode(raw) as Map<String, dynamic>;

class SleepTimerState {
  final DateTime? endsAt; // minutes mode
  final int? tracksLeft; // tracks mode
  const SleepTimerState({required this.endsAt, required this.tracksLeft});
}
