/// Domain models. Mirror the shapes the Papa Audio bridge returns so JSON maps
/// straight in.
library;

class Track {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final String filePath; // original PC path — the /stream key
  final String? artPath;
  final int trackNumber;
  final int discNumber;
  final double duration; // seconds; 0 = unknown until played

  /// Full playable URI (content://, file://, http…). When null the track plays
  /// from the bridge via /stream?path=[filePath]. This is what lets one Track
  /// type cover PC, on-phone, downloaded and YouTube tracks.
  final String? sourceUri;

  /// Full artwork URI (http, file://, or the app's `localart://tid/aid`
  /// convention for MediaStore art). When null, art comes from the bridge's
  /// /art?path=[artPath].
  final String? artUri;

  final int year; // 0 = unknown
  final String? genre;
  final int dateAdded; // epoch seconds (MediaStore convention); 0 = unknown

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.filePath,
    this.album,
    this.artPath,
    this.trackNumber = 0,
    this.discNumber = 1,
    this.duration = 0,
    this.sourceUri,
    this.artUri,
    this.year = 0,
    this.genre,
    this.dateAdded = 0,
  });

  factory Track.fromJson(Map<String, dynamic> j) {
    final id = (j['id'] ?? j['filePath'] ?? '').toString();
    var artUri = j['artUri']?.toString();
    // Heal YT tracks persisted before thumbnails were guaranteed — every
    // video has a ytimg still, so restored queues never show placeholder art.
    if (artUri == null && id.startsWith('yt:')) {
      artUri = 'https://i.ytimg.com/vi/${id.substring(3)}/hqdefault.jpg';
    }
    return Track(
        id: id,
        title: (j['title'] ?? 'Unknown').toString(),
        artist: (j['artist'] ?? 'Unknown Artist').toString(),
        album: j['album']?.toString(),
        filePath: (j['filePath'] ?? '').toString(),
        artPath: j['artPath']?.toString(),
        trackNumber: (j['trackNumber'] ?? 0) is int
            ? (j['trackNumber'] ?? 0)
            : int.tryParse('${j['trackNumber']}') ?? 0,
        discNumber: (j['discNumber'] ?? 1) is int
            ? (j['discNumber'] ?? 1)
            : int.tryParse('${j['discNumber']}') ?? 1,
        duration: (j['duration'] ?? 0).toDouble(),
        sourceUri: j['sourceUri']?.toString(),
        artUri: artUri,
        year: (j['year'] as num?)?.toInt() ?? 0,
        genre: j['genre']?.toString(),
        dateAdded: (j['dateAdded'] as num?)?.toInt() ?? 0,
      );
  }

  /// Round-trips through fromJson — used by playlists/history/queue persistence.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        if (album != null) 'album': album,
        'filePath': filePath,
        if (artPath != null) 'artPath': artPath,
        'trackNumber': trackNumber,
        'discNumber': discNumber,
        'duration': duration,
        if (sourceUri != null) 'sourceUri': sourceUri,
        if (artUri != null) 'artUri': artUri,
        if (year != 0) 'year': year,
        if (genre != null) 'genre': genre,
        if (dateAdded != 0) 'dateAdded': dateAdded,
      };

  /// Stable identity across app runs. Ids are already namespaced by source
  /// ('local:…', 'yt:…', bridge ids are PC file paths), so id alone works.
  String get key => id;
}

class Album {
  final String id;
  final String name;
  final String artist;
  final String? artPath;
  final int? year;
  final bool isHiRes;
  final List<Track> tracks;

  const Album({
    required this.id,
    required this.name,
    required this.artist,
    this.artPath,
    this.year,
    this.isHiRes = false,
    this.tracks = const [],
  });

  factory Album.fromJson(Map<String, dynamic> j) => Album(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? 'Unknown Album').toString(),
        artist: (j['artist'] ?? 'Unknown Artist').toString(),
        artPath: j['artPath']?.toString(),
        year: j['year'] is int ? j['year'] : int.tryParse('${j['year']}'),
        isHiRes: j['isHiRes'] == true,
        tracks: ((j['tracks'] ?? []) as List)
            .map((t) => Track.fromJson(t as Map<String, dynamic>))
            .toList(),
      );

  int get trackCount => tracks.length;
}

/// A Soulseek search result folder (from /api/slsk/search).
class SlskFolder {
  final String username;
  final String folder;
  final int fileCount;
  final int totalSize;
  final int? bitrate;
  final List<String> files;

  const SlskFolder({
    required this.username,
    required this.folder,
    required this.fileCount,
    required this.totalSize,
    this.bitrate,
    this.files = const [],
  });

  factory SlskFolder.fromJson(Map<String, dynamic> j) => SlskFolder(
        username: (j['username'] ?? '').toString(),
        folder: (j['folder'] ?? j['path'] ?? '').toString(),
        fileCount: (j['fileCount'] ?? (j['files'] as List?)?.length ?? 0),
        totalSize: (j['totalSize'] ?? j['size'] ?? 0),
        bitrate: j['bitrate'] is int ? j['bitrate'] : null,
        files: ((j['files'] ?? []) as List).map((f) => f.toString()).toList(),
      );
}

/// A YouTube search result (from /api/youtube/search). The bridge does the
/// actual talking to YouTube; field names are parsed tolerantly since the
/// server evolved over time.
class YtResult {
  final String id; // video id
  final String title;
  final String channel;
  final String? thumbnail;
  final int? durationSec;

  const YtResult({
    required this.id,
    required this.title,
    required this.channel,
    this.thumbnail,
    this.durationSec,
  });

  factory YtResult.fromJson(Map<String, dynamic> j) {
    String id = (j['id'] ?? j['videoId'] ?? '').toString();
    if (id.isEmpty && j['url'] != null) {
      final m = RegExp(r'[?&]v=([\w-]{6,})').firstMatch(j['url'].toString());
      id = m?.group(1) ?? '';
    }
    String? thumb = (j['thumbnail'] ?? j['thumb'])?.toString();
    if (thumb == null && j['thumbnails'] is List && (j['thumbnails'] as List).isNotEmpty) {
      final first = (j['thumbnails'] as List).first;
      thumb = first is Map ? first['url']?.toString() : first?.toString();
    }
    return YtResult(
      id: id,
      title: (j['title'] ?? 'Unknown').toString(),
      channel: (j['channel'] ?? j['author'] ?? j['uploader'] ?? j['channelTitle'] ?? '').toString(),
      thumbnail: thumb,
      durationSec: _parseDuration(j['duration'] ?? j['durationSec'] ?? j['lengthSeconds']),
    );
  }

  /// Accepts 215, "215", or "3:35".
  static int? _parseDuration(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.round();
    final s = v.toString().trim();
    if (s.contains(':')) {
      final parts = s.split(':').map((p) => int.tryParse(p) ?? 0).toList();
      var secs = 0;
      for (final p in parts) {
        secs = secs * 60 + p;
      }
      return secs;
    }
    return int.tryParse(s);
  }
}
