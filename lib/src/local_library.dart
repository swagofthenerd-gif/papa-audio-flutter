import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

/// On-phone music library, read through a small MediaStore platform channel
/// (see MainActivity.kt). This is the native-player trick: MediaStore already
/// indexed every audio file on the device, so the library appears instantly —
/// no folder scanning, no scoped-storage file paths.
class LocalLibrary extends ChangeNotifier {
  static const _ch = MethodChannel('papa.audio/media_store');

  bool permitted = false;
  bool loading = false;
  String? error;
  List<LocalAlbum> albums = [];

  /// Bumped on every (re)load — cheap change detection for list memoization.
  int revision = 0;

  int get trackCount => albums.fold(0, (n, a) => n + a.tracks.length);

  /// Silent init: if permission was already granted, load without prompting.
  Future<void> init() async {
    try {
      permitted = await _ch.invokeMethod<bool>('hasPermission') ?? false;
    } catch (_) {
      permitted = false; // channel missing (e.g. iOS/tests) — tab shows prompt
    }
    if (permitted) await _load();
    notifyListeners();
  }

  /// Ask for READ_MEDIA_AUDIO (or READ_EXTERNAL_STORAGE pre-33) and load.
  Future<bool> requestAndLoad() async {
    try {
      permitted = await _ch.invokeMethod<bool>('requestPermission') ?? false;
    } catch (e) {
      error = 'Media access unavailable: $e';
      permitted = false;
    }
    if (permitted) await _load();
    notifyListeners();
    return permitted;
  }

  Future<void> refresh() => _load().then((_) => notifyListeners());

  Future<void> _load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final rows = await _ch.invokeListMethod<Map>('queryTracks') ?? [];
      albums = _group(rows);
      revision++;
    } catch (e) {
      error = 'Failed to read music library: $e';
    } finally {
      loading = false;
    }
  }

  /// Group MediaStore rows into albums, sorted by artist/name, tracks by
  /// disc+track number.
  static List<LocalAlbum> _group(List<Map> rows) {
    final byAlbum = <int, List<Map>>{};
    for (final r in rows) {
      final albumId = (r['albumId'] as num?)?.toInt() ?? 0;
      byAlbum.putIfAbsent(albumId, () => []).add(r);
    }
    final albums = byAlbum.entries.map((e) {
      final rows = e.value
        ..sort((a, b) {
          final d = ((a['disc'] as num?) ?? 1).compareTo((b['disc'] as num?) ?? 1);
          if (d != 0) return d;
          return ((a['track'] as num?) ?? 0).compareTo((b['track'] as num?) ?? 0);
        });
      final first = rows.first;
      final tracks = rows.map((r) {
        final id = (r['id'] as num).toInt();
        return Track(
          id: 'local:$id',
          title: (r['title'] ?? 'Unknown').toString(),
          artist: (r['artist'] ?? 'Unknown Artist').toString(),
          album: r['album']?.toString(),
          filePath: (r['path'] ?? '').toString(),
          trackNumber: ((r['track'] as num?) ?? 0).toInt() % 1000, // strip disc prefix (CD1 = 1xxx)
          discNumber: ((r['disc'] as num?) ?? 1).toInt(),
          duration: ((r['durationMs'] as num?) ?? 0).toDouble() / 1000.0,
          sourceUri: (r['uri'] ?? '').toString(),
          artUri: 'localart://$id/${e.key}',
          year: ((r['year'] as num?) ?? 0).toInt(),
          genre: r['genre']?.toString(),
          dateAdded: ((r['dateAdded'] as num?) ?? 0).toInt(),
        );
      }).toList();
      return LocalAlbum(
        albumId: e.key,
        name: (first['album'] ?? 'Unknown Album').toString(),
        artist: _albumArtist(rows),
        artTrackId: (first['id'] as num).toInt(),
        tracks: tracks,
      );
    }).toList()
      ..sort((a, b) {
        final r = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
        return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return albums;
  }

  static String _albumArtist(List<Map> rows) {
    final artists = rows.map((r) => (r['artist'] ?? '').toString()).toSet()..remove('');
    if (artists.length == 1) return artists.first;
    return artists.isEmpty ? 'Unknown Artist' : 'Various Artists';
  }

  // ── Artwork ─────────────────────────────────────────────────────────────────
  // MediaStore art can't be loaded as a network image, so it comes over the
  // channel as bytes, memoized per album (art is per-album in practice).

  static final Map<String, Future<Uint8List?>> _artCache = {};

  /// Load art for a `localart://trackId/albumId` URI at roughly [size] px.
  static Future<Uint8List?> artForUri(String localArtUri, {int size = 300}) {
    final m = RegExp(r'^localart://(\d+)/(\d+)$').firstMatch(localArtUri);
    if (m == null) return Future.value(null);
    return art(int.parse(m.group(1)!), int.parse(m.group(2)!), size: size);
  }

  static Future<Uint8List?> art(int trackId, int albumId, {int size = 300}) {
    final key = '$albumId@$size';
    return _artCache.putIfAbsent(key, () async {
      try {
        return await _ch.invokeMethod<Uint8List>('getArt', {
          'trackId': trackId,
          'albumId': albumId,
          'size': size,
        });
      } catch (_) {
        return null;
      }
    });
  }

  /// A URI the media notification can resolve for lock-screen artwork.
  static Uri notificationArtUri(int albumId) =>
      Uri.parse('content://media/external/audio/albumart/$albumId');
}

/// An album assembled from the phone's MediaStore rows.
class LocalAlbum {
  final int albumId;
  final String name;
  final String artist;
  final int artTrackId; // representative track for thumbnail loading
  final List<Track> tracks;

  const LocalAlbum({
    required this.albumId,
    required this.name,
    required this.artist,
    required this.artTrackId,
    required this.tracks,
  });
}
