import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:shared_preferences/shared_preferences.dart';
import 'bridge.dart';
import 'db.dart';
import 'downloads.dart';
import 'history.dart';
import 'local_library.dart';
import 'models.dart';
import 'player_service.dart';
import 'playlists.dart';
import 'queues_store.dart';
import 'selection.dart';
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
  final QueuesStore queues = QueuesStore();
  final TrackSelection selection = TrackSelection();

  // Flush pending listens the moment the app leaves the foreground, so an OS
  // process kill after hours of playback never loses history.
  AppLifecycleListener? _lifecycle;

  bool loading = false;
  String? error;
  List<Album> albums = [];
  bool slskConnected = false;

  String? get baseUrl => bridge.baseUrl;
  bool get configured => bridge.configured;

  /// True once the user chose "use on-phone music only" — lets the app enter
  /// the main shell without a PC bridge so local-library users aren't stranded
  /// on the connect screen.
  bool localOnly = false;

  /// The app can show its main UI once either a bridge is set OR the user opted
  /// into local-only mode.
  bool get ready => configured || localOnly;

  Future<void> enterLocalOnly() async {
    localOnly = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('localOnly', true);
    notifyListeners();
  }

  Future<void> restore() async {
    // Local features first — they work with no bridge at all.
    playerService.history = history;
    _lifecycle ??= AppLifecycleListener(onInactive: () => history.flush());
    final db = await AppDatabase.open();
    await Future.wait([
      downloads.init(),
      playlists.init(db),
      history.init(db),
      settings.init(),
      queues.init(db),
    ]);
    await playerService.applySettings(settings);
    history.listenSecondsProvider = () => settings.listenSeconds;
    playerService.onNewQueue = queues.record;
    await localLibrary.init();
    // Bring back last session's queue (paused) once sources are known.
    await playerService.initPersistence(db);
    final prefs = await SharedPreferences.getInstance();
    localOnly = prefs.getBool('localOnly') ?? false;
    final saved = prefs.getString('bridgeUrl');
    if (saved != null && saved.isNotEmpty) {
      bridge.baseUrl = saved;
      notifyListeners();
      await loadLibrary();
    } else if (localOnly) {
      notifyListeners();
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
      playTrackInList(album.tracks, startIndex);

  /// Honors the configured tap mode: replace the queue with the list, play
  /// just the tapped track, or gently slot it into the current queue.
  Future<void> playTrackInList(List<Track> tracks, int index) {
    switch (settings.tapMode) {
      case TapMode.list:
        return playerService.playQueue(tracks, index);
      case TapMode.single:
        return playerService.playQueue([tracks[index]], 0);
      case TapMode.gentle:
        if (playerService.queue.isEmpty) {
          return playerService.playQueue([tracks[index]], 0);
        }
        return playerService
            .playNext(tracks[index])
            .then((_) => playerService.next());
    }
  }

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
