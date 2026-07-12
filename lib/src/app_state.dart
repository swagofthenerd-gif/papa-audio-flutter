import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'bridge.dart';
import 'downloads.dart';
import 'history.dart';
import 'local_library.dart';
import 'models.dart';
import 'player_service.dart';
import 'playlists.dart';
import 'settings.dart';

/// Central app state: bridge connection, PC library, and the player. Kept small
/// on purpose — screens read exactly what they need and rebuild narrowly.
/// LocalLibrary, DownloadManager, PlaylistsService and HistoryService are their
/// own ChangeNotifiers so each tab rebuilds independently of the bridge state.
class AppState extends ChangeNotifier {
  final Bridge bridge = Bridge();
  late final PlayerService playerService = PlayerService(bridge);
  final LocalLibrary localLibrary = LocalLibrary();
  final DownloadManager downloads = DownloadManager();
  final PlaylistsService playlists = PlaylistsService();
  final HistoryService history = HistoryService();
  final SettingsService settings = SettingsService();

  bool loading = false;
  String? error;
  List<Album> albums = [];
  bool slskConnected = false;

  String? get baseUrl => bridge.baseUrl;
  bool get configured => bridge.configured;

  Future<void> restore() async {
    // Local features first — they work with no bridge at all.
    playerService.history = history;
    await Future.wait([
      downloads.init(),
      playlists.init(),
      history.init(),
      settings.init(),
    ]);
    await playerService.applySettings(settings);
    history.listenSecondsProvider = () => settings.listenSeconds;
    await localLibrary.init();
    // Bring back last session's queue (paused) once sources are known.
    await playerService.initPersistence();
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('bridgeUrl');
    if (saved != null && saved.isNotEmpty) {
      bridge.baseUrl = saved;
      notifyListeners();
      await loadLibrary();
    }
  }

  Future<bool> connect(String url) async {
    var clean = url.trim();
    if (!clean.startsWith('http')) clean = 'http://$clean';
    // Default port if the user typed a bare IP.
    if (!RegExp(r':\d+').hasMatch(clean.replaceFirst('http://', ''))) {
      clean = '$clean:8765';
    }
    final ok = await Bridge.ping(clean);
    if (!ok) {
      error = 'Could not reach $clean';
      notifyListeners();
      return false;
    }
    bridge.baseUrl = clean;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bridgeUrl', clean);
    error = null;
    notifyListeners();
    await loadLibrary();
    return true;
  }

  /// Forget the saved bridge and return to the connect screen.
  Future<void> disconnect() async {
    bridge.baseUrl = null;
    albums = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('bridgeUrl');
    notifyListeners();
  }

  Future<void> loadLibrary() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      albums = await bridge.getLibrary();
      slskConnected = await bridge.slskConnected();
    } catch (e) {
      error = 'Failed to load library: $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> playAlbum(Album album, {int startIndex = 0}) =>
      playerService.playQueue(album.tracks, startIndex);

  Future<void> playTrackInList(List<Track> tracks, int index) =>
      playerService.playQueue(tracks, index);

  /// Play a single YouTube result, streamed through the bridge.
  Future<void> playYt(YtResult v) {
    final t = Track(
      id: 'yt:${v.id}',
      title: v.title,
      artist: v.channel.isEmpty ? 'YouTube' : v.channel,
      filePath: '',
      duration: (v.durationSec ?? 0).toDouble(),
      sourceUri: bridge.ytStreamUrl(v.id),
      artUri: v.thumbnail,
    );
    return playerService.playQueue([t], 0);
  }
}
