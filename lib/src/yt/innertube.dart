import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;

import 'yt_auth.dart';
import 'yt_models.dart';

/// Minimal innertube (youtubei) client for YouTube Music, written from the
/// publicly documented wire format. Two client identities:
///
///  * WEB_REMIX — the music.youtube.com web app. Used for every browse/search
///    surface; with [YtAuth] cookies attached, responses are the user's real
///    personalized feed (home mixes, listen again, history, library).
///  * ANDROID_MUSIC — used only for /player, because it returns direct
///    (uncphered) stream URLs that can be handed straight to the audio player.
///
/// Parsing philosophy: innertube JSON is deeply nested and shifts shape
/// between surfaces and A/B tests, so instead of mirroring the exact tree this
/// walks the JSON recursively and collects every renderer it understands.
/// Unknown nodes are skipped, never fatal — a partially parsed page beats an
/// exception.
class Innertube {
  static const _base = 'https://music.youtube.com/youtubei/v1';
  final YtAuth auth;
  final http.Client _client = http.Client();

  Innertube(this.auth);

  void dispose() => _client.close();

  // ── Raw endpoints ──────────────────────────────────────────────────────────

  Map<String, dynamic> _webContext() => {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': '1.20250115.01.00',
          'hl': 'en',
          'gl': 'US',
        }
      };

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final resp = await _client
        .post(
          Uri.parse('$_base/$path?prettyPrint=false'),
          headers: auth.headers(),
          body: jsonEncode({'context': _webContext(), ...body}),
        )
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw YtException('YT ${resp.statusCode} on /$path');
    }
    // Feed responses are megabytes of JSON — decode off the UI isolate.
    return await compute(_decodeMap, resp.body);
  }

  Future<Map<String, dynamic>> browseRaw(String browseId,
          {String? params}) =>
      _post('browse', {
        'browseId': browseId,
        if (params != null) 'params': params,
      });

  Future<Map<String, dynamic>> searchRaw(String query, {String? params}) =>
      _post('search', {
        'query': query,
        if (params != null) 'params': params,
      });

  Future<Map<String, dynamic>> nextRaw(String videoId,
          {String? playlistId}) =>
      _post('next', {
        'videoId': videoId,
        if (playlistId != null) 'playlistId': playlistId,
      });

  // ── Surfaces ───────────────────────────────────────────────────────────────

  /// The signed-in user's YT Music home feed (mixes, listen again, made for
  /// you…). Anonymous when signed out — still returns generic shelves.
  Future<List<YtShelf>> home() async =>
      parseShelves(await browseRaw('FEmusic_home'));

  Future<List<YtShelf>> explore() async =>
      parseShelves(await browseRaw('FEmusic_explore'));

  Future<List<YtShelf>> charts() async =>
      parseShelves(await browseRaw('FEmusic_charts'));

  Future<List<YtShelf>> moodsAndGenres() async =>
      parseShelves(await browseRaw('FEmusic_moods_and_genres'));

  /// Listening history, sectioned by day, newest first.
  Future<List<YtShelf>> history() async =>
      parseShelves(await browseRaw('FEmusic_history'));

  /// The user's saved/created playlists.
  Future<List<YtShelf>> libraryPlaylists() async =>
      parseShelves(await browseRaw('FEmusic_liked_playlists'));

  /// Artists the user subscribed to / added to library.
  Future<List<YtShelf>> libraryArtists() async =>
      parseShelves(await browseRaw('FEmusic_library_corpus_artists'));

  /// Liked songs — YT Music models them as the special "LM" playlist.
  Future<List<YtShelf>> likedSongs() => playlist('LM');

  /// Any playlist / album-as-playlist. Accepts bare ids or VL-prefixed.
  Future<List<YtShelf>> playlist(String playlistId) async {
    final id = playlistId.startsWith('VL') ? playlistId : 'VL$playlistId';
    return parseShelves(await browseRaw(id));
  }

  /// Artist/channel page (UC…) or album page (MPRE…).
  Future<List<YtShelf>> browsePage(String browseId) async =>
      parseShelves(await browseRaw(browseId));

  /// Radio/related queue for a video — powers "keep playing similar".
  Future<List<YtMusicItem>> related(String videoId) async {
    final shelves = parseShelves(await nextRaw(videoId));
    return [
      for (final s in shelves) ...s.items.where((i) => i.videoId != null)
    ];
  }

  // Public knowledge search filter params (same values every YT Music client
  // sends). If YT rejects one, the catch in search() retries unfiltered.
  static const searchFilters = <String, String>{
    'songs': 'EgWKAQIIAWoKEAkQChAFEAMQBA==',
    'videos': 'EgWKAQIQAWoKEAkQChAFEAMQBA==',
    'albums': 'EgWKAQIYAWoKEAkQChAFEAMQBA==',
    'artists': 'EgWKAQIgAWoKEAkQChAFEAMQBA==',
    'playlists': 'EgWKAQIoAWoKEAkQChAFEAMQBA==',
  };

  Future<List<YtShelf>> search(String query, {String? filter}) async {
    final params = filter != null ? searchFilters[filter] : null;
    try {
      return parseShelves(await searchRaw(query, params: params));
    } on YtException {
      if (params == null) rethrow;
      return parseShelves(await searchRaw(query)); // filter rejected — retry
    }
  }

  // ── Player (stream resolution) ─────────────────────────────────────────────

  /// Resolve a direct audio stream. Uses the ANDROID_MUSIC identity, whose
  /// /player responses carry plain URLs (no signature deciphering step).
  Future<YtStream> playerStream(String videoId) async {
    final headers = auth.headers()
      ..['user-agent'] =
          'com.google.android.apps.youtube.music/7.11.51 (Linux; U; Android 14) gzip';
    final resp = await _client
        .post(
          Uri.parse('$_base/player?prettyPrint=false'),
          headers: headers,
          body: jsonEncode({
            'context': {
              'client': {
                'clientName': 'ANDROID_MUSIC',
                'clientVersion': '7.11.51',
                'androidSdkVersion': 34,
                'hl': 'en',
                'gl': 'US',
              }
            },
            'videoId': videoId,
            'contentCheckOk': true,
            'racyCheckOk': true,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw YtException('YT player ${resp.statusCode}');
    }
    final json = await compute(_decodeMap, resp.body);
    final status = json['playabilityStatus']?['status'];
    if (status != null && status != 'OK') {
      throw YtException('Not playable: $status '
          '${json['playabilityStatus']?['reason'] ?? ''}');
    }
    final sd = json['streamingData'] as Map<String, dynamic>?;
    final formats = [
      ...?(sd?['adaptiveFormats'] as List?),
      ...?(sd?['formats'] as List?),
    ];
    Map<String, dynamic>? best;
    for (final f in formats) {
      if (f is! Map<String, dynamic>) continue;
      final mime = (f['mimeType'] ?? '').toString();
      if (!mime.startsWith('audio/')) continue;
      if (f['url'] == null) continue; // ciphered — skip, another format won't be
      if (best == null ||
          ((f['bitrate'] as num?) ?? 0) > ((best['bitrate'] as num?) ?? 0)) {
        best = f;
      }
    }
    if (best == null) throw YtException('No direct audio stream');
    final expiresIn =
        int.tryParse('${sd?['expiresInSeconds'] ?? ''}') ?? 6 * 3600;
    return YtStream(
      url: best['url'] as String,
      mime: (best['mimeType'] ?? 'audio/mp4').toString(),
      contentLength: int.tryParse('${best['contentLength'] ?? ''}'),
      bitrate: ((best['bitrate'] as num?) ?? 0).toInt(),
      expiresAt:
          DateTime.now().add(Duration(seconds: (expiresIn - 120).clamp(60, 86400))),
    );
  }

  // ── Tolerant parsing ───────────────────────────────────────────────────────

  /// Walk the whole response and collect every shelf-like renderer.
  static List<YtShelf> parseShelves(Map<String, dynamic> root) {
    final shelves = <YtShelf>[];
    _walk(root, (key, node) {
      switch (key) {
        case 'musicCarouselShelfRenderer':
          final title = _text(_dig(node,
                  ['header', 'musicCarouselShelfBasicHeaderRenderer', 'title'])) ??
              '';
          final items = _items(node['contents']);
          if (items.isNotEmpty) shelves.add(YtShelf(title: title, items: items));
        case 'musicShelfRenderer':
        case 'musicPlaylistShelfRenderer':
          final title = _text(node['title']) ?? '';
          final items = _items(node['contents']);
          if (items.isNotEmpty) shelves.add(YtShelf(title: title, items: items));
        case 'gridRenderer':
          final title = _text(_dig(
                  node, ['header', 'gridHeaderRenderer', 'title'])) ??
              '';
          final items = _items(node['items']);
          if (items.isNotEmpty) shelves.add(YtShelf(title: title, items: items));
      }
    });
    return shelves;
  }

  static List<YtMusicItem> _items(dynamic contents) {
    final out = <YtMusicItem>[];
    if (contents is! List) return out;
    for (final c in contents) {
      if (c is! Map) continue;
      final two = c['musicTwoRowItemRenderer'];
      if (two is Map) {
        final item = _twoRow(two.cast<String, dynamic>());
        if (item != null) out.add(item);
        continue;
      }
      final row = c['musicResponsiveListItemRenderer'];
      if (row is Map) {
        final item = _listRow(row.cast<String, dynamic>());
        if (item != null) out.add(item);
      }
    }
    return out;
  }

  /// Carousel/grid card: mixes, albums, artists, playlists, videos.
  static YtMusicItem? _twoRow(Map<String, dynamic> r) {
    final title = _text(r['title']);
    if (title == null || title.isEmpty) return null;
    final subtitle = _text(r['subtitle']) ?? '';
    final thumb = _thumb(_dig(r,
        ['thumbnailRenderer', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']));
    final nav = r['navigationEndpoint'];
    return _fromEndpoint(nav, title: title, subtitle: subtitle, thumb: thumb);
  }

  /// Table row: playlist tracks, search results, history entries.
  static YtMusicItem? _listRow(Map<String, dynamic> r) {
    final cols = r['flexColumns'];
    if (cols is! List || cols.isEmpty) return null;
    String? colText(int i) => i < cols.length
        ? _text(_dig(cols[i],
            ['musicResponsiveListItemFlexColumnRenderer', 'text']))
        : null;
    final title = colText(0);
    if (title == null || title.isEmpty) return null;
    final subtitle = [
      for (var i = 1; i < cols.length; i++)
        if ((colText(i) ?? '').isNotEmpty) colText(i)!
    ].join(' · ');
    final thumb = _thumb(_dig(r,
        ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']));

    // videoId lives either on the title run, the overlay play button, or the
    // row's own playlistItemData.
    String? videoId = _dig(r, ['playlistItemData', 'videoId'])?.toString();
    videoId ??= _findFirst(cols[0], 'videoId')?.toString();
    videoId ??= _findFirst(r['overlay'], 'videoId')?.toString();
    if (videoId != null) {
      return YtMusicItem(
        kind: YtItemKind.song,
        videoId: videoId,
        title: title,
        subtitle: subtitle,
        thumbnail: thumb,
      );
    }
    return _fromEndpoint(r['navigationEndpoint'],
        title: title, subtitle: subtitle, thumb: thumb);
  }

  static YtMusicItem? _fromEndpoint(dynamic nav,
      {required String title, required String subtitle, String? thumb}) {
    if (nav is! Map) return null;
    final watch = nav['watchEndpoint'];
    if (watch is Map && watch['videoId'] != null) {
      return YtMusicItem(
        kind: YtItemKind.song,
        videoId: watch['videoId'].toString(),
        playlistId: watch['playlistId']?.toString(),
        title: title,
        subtitle: subtitle,
        thumbnail: thumb,
      );
    }
    final watchPl = nav['watchPlaylistEndpoint'];
    if (watchPl is Map && watchPl['playlistId'] != null) {
      return YtMusicItem(
        kind: YtItemKind.playlist,
        playlistId: watchPl['playlistId'].toString(),
        title: title,
        subtitle: subtitle,
        thumbnail: thumb,
      );
    }
    final browse = nav['browseEndpoint'];
    if (browse is Map && browse['browseId'] != null) {
      final id = browse['browseId'].toString();
      final kind = id.startsWith('MPRE')
          ? YtItemKind.album
          : id.startsWith('UC')
              ? YtItemKind.artist
              : YtItemKind.playlist;
      return YtMusicItem(
        kind: kind,
        browseId: id,
        playlistId:
            kind == YtItemKind.playlist && id.startsWith('VL') ? id.substring(2) : null,
        title: title,
        subtitle: subtitle,
        thumbnail: thumb,
      );
    }
    return null;
  }

  // ── JSON helpers ───────────────────────────────────────────────────────────

  static void _walk(dynamic node, void Function(String key, Map node) visit,
      [int depth = 0]) {
    if (depth > 40) return;
    if (node is Map) {
      for (final e in node.entries) {
        if (e.value is Map) visit(e.key.toString(), e.value as Map);
        _walk(e.value, visit, depth + 1);
      }
    } else if (node is List) {
      for (final v in node) {
        _walk(v, visit, depth + 1);
      }
    }
  }

  static dynamic _dig(dynamic node, List<String> path) {
    var cur = node;
    for (final p in path) {
      if (cur is Map) {
        cur = cur[p];
      } else {
        return null;
      }
    }
    return cur;
  }

  /// First value for [key] anywhere under [node].
  static dynamic _findFirst(dynamic node, String key, [int depth = 0]) {
    if (depth > 20) return null;
    if (node is Map) {
      if (node[key] != null && node[key] is! Map && node[key] is! List) {
        return node[key];
      }
      for (final v in node.values) {
        final r = _findFirst(v, key, depth + 1);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final v in node) {
        final r = _findFirst(v, key, depth + 1);
        if (r != null) return r;
      }
    }
    return null;
  }

  static String? _text(dynamic t) {
    if (t is! Map) return null;
    final simple = t['simpleText'];
    if (simple is String) return simple;
    final runs = t['runs'];
    if (runs is List) {
      return runs
          .whereType<Map>()
          .map((r) => (r['text'] ?? '').toString())
          .join();
    }
    return null;
  }

  static String? _thumb(dynamic thumbs) {
    if (thumbs is! List || thumbs.isEmpty) return null;
    final last = thumbs.last;
    return last is Map ? last['url']?.toString() : null;
  }
}

class YtException implements Exception {
  final String message;
  YtException(this.message);
  @override
  String toString() => message;
}

/// Isolate worker for [compute] — innertube responses are large.
Map<String, dynamic> _decodeMap(String raw) =>
    jsonDecode(raw) as Map<String, dynamic>;
