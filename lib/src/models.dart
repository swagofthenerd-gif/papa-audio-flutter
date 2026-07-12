/// Domain models. Mirror the shapes the Papa Audio bridge returns so JSON maps
/// straight in.

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
  });

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: (j['id'] ?? j['filePath'] ?? '').toString(),
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
      );
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
