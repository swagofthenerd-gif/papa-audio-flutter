import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:shared_preferences/shared_preferences.dart';
import 'art_color.dart';
import 'audio_format.dart';
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
import 'yt/yt_auth.dart';
import 'yt/yt_models.dart';
import 'yt/yt_service.dart';
import 'yt/yt_video.dart';

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
  final YtAuth ytAuth = YtAuth();
  late final YtService yt = YtService(ytAuth);
  late final YtVideoController ytVideo = YtVideoController(yt.tube);
  final TrackSelection selection = TrackSelection();
  late final ArtColorService artColors =
      ArtColorService(bridgeArtUrl: (p) => bridge.artUrl(p, width: 96));
  late final AudioFormatService audioFormats =
      AudioFormatService(resolveYt: (id) => yt.resolver.resolve(id));
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
    // YouTube Music: auth + feed cache load, and on-device stream resolution.
    await ytAuth.init(db);
    playerService.ytResolver = yt.resolver;
    yt.init(db); // fire-and-forget; home paints from cache, refreshes behind
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

  /// Play a single YouTube result. Streams on-device (lazy extraction); the
  /// null sourceUri routes it through YtLazyAudioSource in the player.
  Future<void> playYt(YtResult v) {
    final t = Track(
      id: 'yt:${v.id}',
      title: v.title,
      artist: v.channel.isEmpty ? 'YouTube' : v.channel,
      filePath: '',
      duration: (v.durationSec ?? 0).toDouble(),
      artUri: v.thumbnail,
    );
    return playYtTrack(t);
  }

  /// Play a YT track and quietly grow the queue into its radio: related tracks
  /// append behind it, so playback continues like YT Music's autoplay.
  Future<void> playYtTrack(Track t) async {
    await playerService.playQueue([t], 0);
    final id = t.id.startsWith('yt:') ? t.id.substring(3) : t.id;
    try {
      final related = await yt.tube.related(id);
      // The user may have moved on while we fetched — only extend if this
      // track still owns the queue.
      if (playerService.currentTrack?.id != t.id) return;
      var added = 0;
      for (final item in related) {
        final rt = item.toTrack();
        if (rt == null || rt.id == t.id) continue;
        await playerService.addToQueue(rt);
        if (++added >= 20) break;
      }
    } catch (_) {} // radio is a bonus — the tapped track already plays
  }

  /// Play any YT Music item: songs start radio; albums/playlists/artists fetch
  /// their tracks and replace the queue.
  Future<void> playYtItem(YtMusicItem item) async {
    final t = item.toTrack();
    if (t != null) return playYtTrack(t);
    final shelves = item.playlistId != null
        ? await yt.tube.playlist(item.playlistId!)
        : item.browseId != null
            ? await yt.tube.browsePage(item.browseId!)
            : const <YtShelf>[];
    final tracks = <Track>[];
    final seen = <String>{};
    for (final s in shelves) {
      for (final i in s.items) {
        final rt = i.toTrack();
        if (rt != null && seen.add(rt.id)) tracks.add(rt);
      }
    }
    if (tracks.isNotEmpty) await playerService.playQueue(tracks, 0);
  }

  /// Resolve a YT playlist/album to its tracks (deduped, in order).
  Future<List<Track>> ytItemTracks(YtMusicItem item) async {
    final shelves = item.playlistId != null
        ? await yt.tube.playlist(item.playlistId!)
        : item.browseId != null
            ? await yt.tube.browsePage(item.browseId!)
            : const <YtShelf>[];
    final tracks = <Track>[];
    final seen = <String>{};
    for (final s in shelves) {
      for (final i in s.items) {
        final rt = i.toTrack();
        if (rt != null && seen.add(rt.id)) tracks.add(rt);
      }
    }
    return tracks;
  }

  /// Import a YT playlist/album into a local playlist so it lives in the
  /// library (and works offline once its tracks are downloaded). Returns the
  /// created playlist, or null if it had no playable tracks.
  Future<Playlist?> importYtPlaylist(YtMusicItem item) async {
    final tracks = await ytItemTracks(item);
    if (tracks.isEmpty) return null;
    final pl = await playlists.create(item.title);
    await playlists.addTracks(pl, tracks);
    return pl;
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
