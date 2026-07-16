import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:shared_preferences/shared_preferences.dart';
import 'art_color.dart';
import 'bridge.dart';
import 'db.dart';
import 'downloads.dart';
import 'history.dart';
import 'lyrics.dart';
import 'local_library.dart';
import 'models.dart';
import 'player_service.dart';
import 'playlists.dart';
import 'queues_store.dart';
import 'recommendations.dart';
import 'selection.dart';
import 'settings.dart';
import 'waveform.dart';

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
  final RecommendationService recommendations = RecommendationService();
  final TrackSelection selection = TrackSelection();
  late final ArtColorService artColors =
      ArtColorService(bridgeArtUrl: (p) => bridge.artUrl(p, width: 96));
  LyricsService? lyrics; // created once the DB is open
  WaveformService? waveforms;

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
    playerService.history = history;
    _lifecycle ??= AppLifecycleListener(onInactive: () => history.flush());

    // `ready` flips FIRST — the shell must appear within a frame of launch,
    // never after the DB/migration/library chain. (Perf audit finding.)
    final prefs = await SharedPreferences.getInstance();
    localOnly = prefs.getBool('localOnly') ?? false;
    final saved = prefs.getString('bridgeUrl');
    if (saved != null && saved.isNotEmpty) bridge.baseUrl = saved;
    notifyListeners();

    // Independent init chains run concurrently; join once at the end.
    final dbFuture = AppDatabase.open();
    final localFuture = localLibrary.init();
    final settingsFuture =
        settings.init().then((_) => playerService.applySettings(settings));
    final downloadsFuture = downloads.init();
    final db = await dbFuture;
    lyrics = LyricsService(db);
    waveforms = WaveformService(db);
    await Future.wait([
      playlists.init(db),
      history.init(db),
      queues.init(db),
      localFuture,
      settingsFuture,
      downloadsFuture,
    ]);
    history.listenSecondsProvider = () => settings.listenSeconds;
    history.thresholdProvider = (t) {
      if (settings.listenPercentMode && t.duration > 0) {
        return t.duration * settings.listenPercent / 100;
      }
      final want = settings.listenSeconds.toDouble();
      return t.duration > 0 ? want.clamp(0, t.duration * 0.5) : want;
    };
    playerService.onNewQueue = queues.record;
    // Bring back last session's queue (paused) once sources are known.
    await playerService.initPersistence(db);
    if (bridge.configured) await loadLibrary();
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
      playTrackInList(album.tracks, startIndex,
          collectionId: 'palbum:${album.id}');

  /// Honors the configured tap mode: replace the queue with the list, play
  /// just the tapped track, or gently slot it into the current queue.
  /// [collectionId] lets the collection remember its listening position.
  Future<void> playTrackInList(List<Track> tracks, int index,
      {String? collectionId}) {
    switch (settings.tapMode) {
      case TapMode.list:
        return playerService.playQueue(tracks, index,
            collectionId: collectionId);
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

  /// Resolve the player's saved resume points into playable "Jump back in"
  /// cards. Only collections we can reconstruct from current in-memory data are
  /// returned (albums / local albums / playlists); others are skipped.
  Future<List<JumpBackItem>> jumpBackIn({int limit = 8}) async {
    final rows = await playerService.recentCollections(limit: limit * 2);
    final out = <JumpBackItem>[];
    for (final r in rows) {
      final cid = r.collectionId;
      String? title, artUri, artPath;
      List<Track>? tracks;
      if (cid.startsWith('palbum:')) {
        final id = cid.substring(7);
        final a = albums.where((x) => x.id == id).firstOrNull;
        if (a != null) {
          title = a.name;
          tracks = a.tracks;
          artPath = a.artPath;
        }
      } else if (cid.startsWith('lalbum:')) {
        final id = int.tryParse(cid.substring(7));
        final a =
            localLibrary.albums.where((x) => x.albumId == id).firstOrNull;
        if (a != null) {
          title = a.name;
          tracks = a.tracks;
          artUri = 'localart://${a.artTrackId}/${a.albumId}';
        }
      } else if (cid.startsWith('playlist:')) {
        final id = cid.substring(9);
        final p = playlists.playlists.where((x) => x.id == id).firstOrNull;
        if (p != null && p.tracks.isNotEmpty) {
          title = p.name;
          tracks = p.tracks;
          artUri = p.tracks.first.artUri;
          artPath = p.tracks.first.artPath;
        }
      }
      if (title == null || tracks == null || tracks.isEmpty) continue;
      final idx = r.index.clamp(0, tracks.length - 1);
      out.add(JumpBackItem(
        collectionId: cid,
        title: title,
        subtitle: r.trackTitle ?? tracks[idx].title,
        artUri: artUri ?? tracks[idx].artUri,
        artPath: artPath ?? tracks[idx].artPath,
        tracks: tracks,
        index: idx,
        positionMs: r.positionMs,
      ));
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Resume a "Jump back in" card at its saved track and position.
  Future<void> resumeJumpBack(JumpBackItem item) => playerService.playQueue(
      item.tracks, item.index,
      collectionId: item.collectionId,
      startPosition: Duration(milliseconds: item.positionMs));

  /// Play a generated mix as a fresh (non-collection) queue.
  Future<void> playMix(List<Track> tracks) =>
      playerService.playQueue(tracks, 0);

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

/// A resolved home "Jump back in" card.
class JumpBackItem {
  final String collectionId;
  final String title;
  final String subtitle;
  final String? artUri;
  final String? artPath;
  final List<Track> tracks;
  final int index;
  final int positionMs;
  const JumpBackItem({
    required this.collectionId,
    required this.title,
    required this.subtitle,
    this.artUri,
    this.artPath,
    required this.tracks,
    required this.index,
    required this.positionMs,
  });
}
