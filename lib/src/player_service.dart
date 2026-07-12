import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'models.dart';
import 'bridge.dart';

/// Native gapless playback via just_audio + a background/lock-screen handler.
/// This is the layer that gives the "buttery" feel — audio runs on the platform
/// side, not in a JS bridge.
class PlayerService {
  final Bridge bridge;
  final AudioPlayer _player = AudioPlayer();
  List<Track> _queue = [];

  PlayerService(this.bridge);

  AudioPlayer get player => _player;
  List<Track> get queue => _queue;

  Stream<PlayerState> get playerState => _player.playerStateStream;
  Stream<Duration> get position => _player.positionStream;
  Stream<Duration?> get duration => _player.durationStream;
  Stream<int?> get currentIndex => _player.currentIndexStream;

  Track? get currentTrack {
    final i = _player.currentIndex;
    if (i == null || i < 0 || i >= _queue.length) return null;
    return _queue[i];
  }

  AudioSource _sourceFor(Track t) {
    final url = bridge.streamUrl(t.filePath);
    return AudioSource.uri(
      Uri.parse(url),
      tag: MediaItem(
        id: t.id,
        title: t.title,
        artist: t.artist,
        album: t.album,
        artUri: bridge.artUrl(t.artPath, width: 512) != null
            ? Uri.parse(bridge.artUrl(t.artPath, width: 512)!)
            : null,
      ),
    );
  }

  Future<void> playQueue(List<Track> tracks, int startIndex) async {
    _queue = tracks;
    final playlist = ConcatenatingAudioSource(
      children: tracks.map(_sourceFor).toList(),
    );
    await _player.setAudioSource(playlist, initialIndex: startIndex);
    _player.play();
  }

  Future<void> togglePlay() =>
      _player.playing ? _player.pause() : _player.play();
  Future<void> next() => _player.seekToNext();
  Future<void> previous() => _player.seekToPrevious();
  Future<void> seek(Duration d) => _player.seek(d);
  Future<void> skipTo(int index) => _player.seek(Duration.zero, index: index);

  Future<void> dispose() => _player.dispose();
}
