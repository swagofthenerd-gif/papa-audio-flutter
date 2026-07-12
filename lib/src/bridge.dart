import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

/// HTTP client for the Papa Audio PC bridge (the Node server in
/// ~/flac-player/bridge-server, default port 8765). All the "special" features
/// — PC library, lossless streaming, Soulseek, YouTube — already live there, so
/// the app just talks to these endpoints.
class Bridge {
  String? baseUrl; // e.g. http://192.168.18.4:8765

  Bridge([this.baseUrl]);

  bool get configured => baseUrl != null && baseUrl!.isNotEmpty;

  Uri _u(String path, [Map<String, String>? q]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: q);

  /// Reachability probe against a candidate URL.
  static Future<bool> ping(String url) async {
    try {
      final r = await http
          .get(Uri.parse('$url/api/health'))
          .timeout(const Duration(seconds: 4));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Streaming URL for a track. `raw` forces the original lossless file
  /// (used for downloads); otherwise the server may transcode off-LAN.
  String streamUrl(String filePath, {bool raw = false}) {
    final u = _u('/stream', {
      'path': filePath,
      if (raw) 'raw': '1',
    });
    return u.toString();
  }

  /// Album/track artwork URL. Pass a width for grid thumbnails.
  String? artUrl(String? artPath, {int? width}) {
    if (artPath == null || artPath.isEmpty) return null;
    // Local/remote absolute URIs are served directly.
    if (RegExp(r'^(file|content|https?):').hasMatch(artPath)) return artPath;
    return _u('/art', {
      'path': artPath,
      if (width != null) 'w': '$width',
    }).toString();
  }

  Future<List<Album>> getLibrary() async {
    final r = await http.get(_u('/api/library')).timeout(const Duration(seconds: 20));
    final body = jsonDecode(r.body);
    final list = (body is Map ? body['albums'] : body) as List? ?? [];
    return list.map((a) => Album.fromJson(a as Map<String, dynamic>)).toList();
  }

  // ── Soulseek ────────────────────────────────────────────────────────────────
  Future<bool> slskConnected() async {
    try {
      final r = await http.get(_u('/api/slsk/status')).timeout(const Duration(seconds: 6));
      final j = jsonDecode(r.body);
      return j['connected'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<SlskFolder>> slskSearch(String query) async {
    final r = await http
        .get(_u('/api/slsk/search', {'query': query}))
        .timeout(const Duration(seconds: 40));
    final body = jsonDecode(r.body);
    final list = (body is Map ? (body['results'] ?? body['folders']) : body) as List? ?? [];
    return list.map((f) => SlskFolder.fromJson(f as Map<String, dynamic>)).toList();
  }

  Future<void> slskDownload(SlskFolder folder) async {
    await http.post(
      _u('/api/slsk/download'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': folder.username,
        'folder': folder.folder,
        'files': folder.files,
      }),
    );
  }

  Future<List<dynamic>> slskTransfers() async {
    try {
      final r = await http.get(_u('/api/slsk/transfers')).timeout(const Duration(seconds: 8));
      final j = jsonDecode(r.body);
      return (j is List) ? j : (j['transfers'] as List? ?? []);
    } catch (_) {
      return [];
    }
  }

  // ── YouTube ─────────────────────────────────────────────────────────────────
  // The bridge proxies YouTube (search / audio stream / download-to-library).
  // Field names are parsed tolerantly — see YtResult.fromJson.

  Future<List<YtResult>> ytSearch(String query) async {
    final r = await http
        .get(_u('/api/youtube/search', {'query': query, 'q': query}))
        .timeout(const Duration(seconds: 30));
    final body = jsonDecode(r.body);
    final list =
        (body is Map ? (body['results'] ?? body['items'] ?? body['videos']) : body) as List? ?? [];
    return list
        .map((v) => YtResult.fromJson(v as Map<String, dynamic>))
        .where((v) => v.id.isNotEmpty)
        .toList();
  }

  /// Audio stream URL for a YouTube video (the server extracts/transcodes).
  String ytStreamUrl(String videoId) =>
      _u('/api/youtube/stream', {'id': videoId}).toString();

  /// Ask the PC to download a YouTube video into the library.
  Future<void> ytDownload(YtResult v) async {
    await http.post(
      _u('/api/youtube/download'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'id': v.id,
        'url': 'https://www.youtube.com/watch?v=${v.id}',
        'title': v.title,
      }),
    );
  }
}
