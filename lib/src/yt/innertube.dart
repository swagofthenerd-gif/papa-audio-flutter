import 'dart:convert';

import 'package:flutter/foundation.dart' show compute, debugPrint, kDebugMode;
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
    // Two tries with a short backoff: transient 5xx / network blips are common
    // and a single retry turns most of them into a normal load.
    YtException? last;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) await Future.delayed(const Duration(milliseconds: 400));
      try {
        final resp = await _client
            .post(
              Uri.parse('$_base/$path?prettyPrint=false'),
              headers: auth.headers(),
              body: jsonEncode({'context': _webContext(), ...body}),
            )
            .timeout(const Duration(seconds: 20));
        if (resp.statusCode == 200) {
          // Megabytes of JSON — decode off the UI isolate.
          return await compute(_decodeMap, resp.body);
        }
        last = YtException('YT ${resp.statusCode} on /$path');
        if (resp.statusCode < 500 && resp.statusCode != 429) break; // not transient
      } catch (e) {
        last = YtException('YT /$path failed: $e');
      }
    }
    throw last ?? YtException('YT /$path failed');
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

  /// Fetch the next page of a surface via its continuation token.
  Future<YtPage> continued(String token) async {
    final json = await _post('browse', {'continuation': token});
    return YtPage(
      shelves: parseShelves(json),
      continuation: _findContinuation(json),
    );
  }

  /// Browse a surface and also surface its continuation token for paging.
  Future<YtPage> browsePaged(String browseId, {String? params}) async {
    final json = await browseRaw(browseId, params: params);
    return YtPage(
      shelves: parseShelves(json),
      continuation: _findContinuation(json),
    );
  }

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

  /// New releases (albums/singles) — includes the signed-in user's
  /// subscription-driven releases at the top when logged in.
  Future<List<YtShelf>> newReleases() async =>
      parseShelves(await browseRaw('FEmusic_new_releases'));

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

  /// Resolve a YouTube Music artist page from a name — used by every "tap the
  /// artist" affordance to open the real artist experience (top songs, albums,
  /// singles, "fans might also like") instead of a local name search. Prefers
  /// an exact-name channel match, else the first artist result.
  Future<YtMusicItem?> findArtist(String name) async {
    final shelves = await search(name, filter: 'artists');
    final wanted = <YtMusicItem>[];
    for (final s in shelves) {
      for (final it in s.items) {
        if ((it.kind == YtItemKind.artist || it.kind == YtItemKind.channel) &&
            it.browseId != null) {
          wanted.add(it);
        }
      }
    }
    if (wanted.isEmpty) return null;
    final norm = name.toLowerCase().trim();
    for (final it in wanted) {
      if (it.title.toLowerCase().trim() == norm) return it;
    }
    return wanted.first;
  }

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

  // /player client identities whose responses carry plain (unciphered) URLs.
  // Verified against live YT (2026-07): ANDROID_MUSIC returns LOGIN_REQUIRED
  // when anonymous (works signed-in with premium-quality formats); ANDROID_VR
  // and a *current* IOS identity both resolve anonymously. IOS versions that
  // fall too far behind get a 400 FAILED_PRECONDITION, so bump these when
  // resolution starts failing across the board.
  static const _androidMusicClient = {
    'clientName': 'ANDROID_MUSIC',
    'clientVersion': '7.11.51',
    'androidSdkVersion': 34,
    'hl': 'en',
    'gl': 'US',
  };
  static const _iosClient = {
    'clientName': 'IOS',
    'clientVersion': '20.10.4',
    'deviceMake': 'Apple',
    'deviceModel': 'iPhone16,2',
    'osName': 'iPhone',
    'osVersion': '18.3.2.22D82',
    'hl': 'en',
    'gl': 'US',
  };
  static const _androidVrClient = {
    'clientName': 'ANDROID_VR',
    'clientVersion': '1.62.27',
    'deviceMake': 'Oculus',
    'deviceModel': 'Quest 3',
    'osName': 'Android',
    'osVersion': '12L',
    'androidSdkVersion': 32,
    'hl': 'en',
    'gl': 'US',
  };

  /// UAs that must accompany both the /player call and any fetch of the URLs
  /// it returns (googlevideo stalls mismatched user-agents).
  static const iosUserAgent =
      'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)';
  static const androidMusicUserAgent =
      'com.google.android.apps.youtube.music/7.11.51 (Linux; U; Android 14) gzip';
  static const androidVrUserAgent =
      'com.google.android.apps.youtube.vr.oculus/1.62.27 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip';

  // ANDROID_MUSIC talks to the music host (its cookies/session live there);
  // IOS and ANDROID_VR are plain-YouTube apps and 400 on the music host.
  static const _wwwBase = 'https://www.youtube.com/youtubei/v1';

  Future<Map<String, dynamic>> _playerJson(
      String videoId, Map<String, dynamic> client, String userAgent,
      {String base = _wwwBase, bool authed = false}) async {
    // Native app clients 400 on the web-style origin/x-goog headers that
    // auth.headers() sends — they want a bare app request. Only the signed-in
    // ANDROID_MUSIC call carries the web session headers (cookies + hash).
    final headers = authed
        ? (auth.headers()..['user-agent'] = userAgent)
        : {'content-type': 'application/json', 'user-agent': userAgent};
    final resp = await _client
        .post(
          Uri.parse('$base/player?prettyPrint=false'),
          headers: headers,
          body: jsonEncode({
            'context': {'client': client},
            'videoId': videoId,
            'contentCheckOk': true,
            'racyCheckOk': true,
          }),
        )
        // ANDROID_VR is the only anonymous client that serves *complete*
        // songs; IOS is capped to ~60s. On a slow mobile connection VR can
        // take >8s, so keep a forgiving timeout — cutting VR off early and
        // failing over to IOS is exactly what makes tracks stop after a
        // minute. 15s fails a genuinely hung attempt without starving VR.
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw YtException('YT player ${resp.statusCode}', videoId: videoId);
    }
    final json = await compute(_decodeMap, resp.body);
    final status = json['playabilityStatus']?['status'];
    if (status != null && status != 'OK') {
      // Typed so callers can distinguish "sign in", "region blocked", "gone".
      throw YtException.playability(
          status.toString(), json['playabilityStatus']?['reason']?.toString(),
          videoId: videoId);
    }
    return json;
  }

  // The client that resolved the previous track. Leading with it skips the
  // failed round-trips that made every track-start pay for dead clients
  // (e.g. a bot-gated ANDROID_VR adding a full request before each song).
  static String? _lastGoodPlayerClient;

  /// Resolve a direct audio stream. Signed in, ANDROID_MUSIC leads (best
  /// quality); anonymous, it always answers LOGIN_REQUIRED so lead with the
  /// clients that resolve without an account.
  Future<YtStream> playerStream(String videoId) async {
    var clients = auth.signedIn
        ? [
            (_androidMusicClient, androidMusicUserAgent, _base),
            (_androidVrClient, androidVrUserAgent, _wwwBase),
            (_iosClient, iosUserAgent, _wwwBase),
          ]
        : [
            // ANDROID_VR leads: it's the only anonymous client whose URLs
            // serve the whole file. IOS resolves more videos but its
            // anonymous URLs are PO-token-capped to the first ~1 MB (~60 s of
            // opus) — a preview, not a stream — so it's strictly a fallback.
            (_androidVrClient, androidVrUserAgent, _wwwBase),
            (_iosClient, iosUserAgent, _wwwBase),
          ];
    final lastGood = _lastGoodPlayerClient;
    if (lastGood != null) {
      clients = [
        ...clients.where((c) => c.$1['clientName'] == lastGood),
        ...clients.where((c) => c.$1['clientName'] != lastGood),
      ];
    }
    YtException? last;
    for (final client in clients) {
      try {
        final json = await _playerJson(videoId, client.$1, client.$2,
            base: client.$3,
            authed: auth.signedIn && client.$1 == _androidMusicClient);
        final s = _bestAudio(json, client.$2);
        if (s != null) {
          // Only make FULL-stream clients sticky. IOS anonymous URLs are
          // PO-token-capped to ~1 MB (~60 s), so if we stuck to IOS every
          // track would cut out after a minute and VR would never get
          // re-probed. Leave lastGood unset (or on VR/MUSIC) in that case.
          final name = client.$1['clientName'] as String;
          if (name != 'IOS' || auth.signedIn) {
            _lastGoodPlayerClient = name;
          }
          return s;
        }
        last = YtException('No direct audio stream', videoId: videoId);
      } on YtException catch (e) {
        debugPrint(
            '[yt] player ${client.$1['clientName']} failed: ${e.message} ${e.playabilityStatus ?? ''}');
        last = e;
        // LOGIN_REQUIRED is client-specific (ANDROID_MUSIC anonymously) — the
        // next client may still resolve. Other playability blocks (region,
        // gone, age) apply to the video itself, so stop.
        if (e.playabilityStatus != null &&
            e.playabilityStatus != 'LOGIN_REQUIRED') {
          break;
        }
      }
    }
    throw last ?? YtException('No stream', videoId: videoId);
  }

  /// Resolve a muxed (audio+video) stream URL for the video toggle. Muxed
  /// formats live in `formats` (e.g. itag 18, 360p) and carry their own audio.
  Future<String?> playerVideo(String videoId) async {
    try {
      // ANDROID_VR is the client that still returns muxed itag-18 formats.
      final json =
          await _playerJson(videoId, _androidVrClient, androidVrUserAgent);
      final sd = json['streamingData'] as Map<String, dynamic>?;
      Map<String, dynamic>? best;
      for (final f in (sd?['formats'] as List? ?? [])) {
        if (f is! Map<String, dynamic>) continue;
        final mime = (f['mimeType'] ?? '').toString();
        if (!mime.startsWith('video/') || f['url'] == null) continue;
        if (best == null ||
            ((f['width'] as num?) ?? 0) > ((best['width'] as num?) ?? 0)) {
          best = f;
        }
      }
      return best?['url'] as String?;
    } catch (_) {
      return null; // video is optional — caller keeps audio
    }
  }

  static YtStream? _bestAudio(Map<String, dynamic> json, String userAgent) {
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
      if (f['url'] == null) continue; // ciphered — skip
      if (best == null ||
          ((f['bitrate'] as num?) ?? 0) > ((best['bitrate'] as num?) ?? 0)) {
        best = f;
      }
    }
    if (best == null) return null;
    final expiresIn =
        int.tryParse('${sd?['expiresInSeconds'] ?? ''}') ?? 6 * 3600;
    return YtStream(
      url: best['url'] as String,
      mime: (best['mimeType'] ?? 'audio/mp4').toString(),
      contentLength: int.tryParse('${best['contentLength'] ?? ''}'),
      bitrate: ((best['bitrate'] as num?) ?? 0).toInt(),
      expiresAt:
          DateTime.now().add(Duration(seconds: (expiresIn - 120).clamp(60, 86400))),
      userAgent: userAgent,
    );
  }

  // ── Tolerant parsing ───────────────────────────────────────────────────────

  /// Walk the whole response and collect every shelf-like renderer.
  static List<YtShelf> parseShelves(Map<String, dynamic> root) {
    final shelves = <YtShelf>[];
    // Diagnosis aid: shelf-shaped renderers the switch below doesn't handle.
    final skipped = <String>{};
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
        // 2026 search layout: the "Top result" card plus per-type sections of
        // bare musicResponsiveListItemRenderers, no musicShelfRenderer at all.
        case 'musicCardShelfRenderer':
          final items = _items(node['contents']);
          if (items.isNotEmpty) {
            shelves.add(YtShelf(title: _text(node['header']) ?? '', items: items));
          }
        case 'itemSectionRenderer':
          // Only collect direct list items; on other surfaces this renderer
          // merely wraps shelves that are parsed by their own cases above.
          final direct = [
            for (final c in (node['contents'] as List? ?? []))
              if (c is Map<String, dynamic> &&
                  c.containsKey('musicResponsiveListItemRenderer'))
                c
          ];
          final items = _items(direct);
          if (items.isNotEmpty) shelves.add(YtShelf(title: '', items: items));
        // Signed-in home: hero carousel at the top, same item shape as the
        // basic carousel but a different header renderer.
        case 'musicImmersiveCarouselShelfRenderer':
          final title = _text(_dig(node, [
                'header',
                'musicImmersiveCarouselShelfBasicHeaderRenderer',
                'title'
              ])) ??
              _text(_findFirstMap(node['header'], 'title')) ??
              '';
          final items = _items(node['contents']);
          if (items.isNotEmpty) shelves.add(YtShelf(title: title, items: items));
        case 'musicTastebuilderShelfRenderer':
          break; // "pick your artists" promo — deliberately not a shelf
        default:
          if (kDebugMode &&
              key.endsWith('Renderer') &&
              (node['contents'] is List || node['items'] is List)) {
            skipped.add(key);
          }
      }
    });
    if (kDebugMode && skipped.isNotEmpty) {
      debugPrint('[yt] parseShelves: ${shelves.length} shelves; '
          'skipped renderers: ${skipped.join(', ')}');
    }
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
            ['thumbnailRenderer', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails'])) ??
        _thumbDeep(r['thumbnailRenderer']);
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
            ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails'])) ??
        _thumbDeep(r['thumbnail']);

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

  /// First Map stored under [key] anywhere under [node] (e.g. a `title`
  /// text object inside an unknown header renderer).
  static Map? _findFirstMap(dynamic node, String key, [int depth = 0]) {
    if (depth > 20) return null;
    if (node is Map) {
      if (node[key] is Map) return node[key] as Map;
      for (final v in node.values) {
        final r = _findFirstMap(v, key, depth + 1);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final v in node) {
        final r = _findFirstMap(v, key, depth + 1);
        if (r != null) return r;
      }
    }
    return null;
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

  /// Fallback thumbnail extraction: find the first `thumbnails` list anywhere
  /// under [node]. Covers renderer variants (croppedSquareThumbnailRenderer
  /// and friends) whose nesting differs from the classic path.
  static String? _thumbDeep(dynamic node, [int depth = 0]) {
    if (depth > 8) return null;
    if (node is Map) {
      if (node['thumbnails'] is List) return _thumb(node['thumbnails']);
      for (final v in node.values) {
        final r = _thumbDeep(v, depth + 1);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final v in node) {
        final r = _thumbDeep(v, depth + 1);
        if (r != null) return r;
      }
    }
    return null;
  }

  /// First continuation token anywhere in the response (YT nests it under
  /// several renderer-specific keys; the token itself is always `continuation`).
  static String? _findContinuation(Map<String, dynamic> root) {
    String? found;
    _walk(root, (key, node) {
      if (found != null) return;
      if (key == 'continuationItemRenderer' || key == 'nextContinuationData') {
        found = _findFirst(node, 'token')?.toString() ??
            _findFirst(node, 'continuation')?.toString();
      }
    });
    return found;
  }
}

/// A page of shelves plus the token to fetch the next page (null when the
/// surface is exhausted).
class YtPage {
  final List<YtShelf> shelves;
  final String? continuation;
  const YtPage({required this.shelves, this.continuation});
}

class YtException implements Exception {
  final String message;
  final String? videoId;

  /// Non-null when YouTube reported a playabilityStatus other than OK
  /// (LOGIN_REQUIRED, UNPLAYABLE, LIVE_STREAM_OFFLINE, ERROR…). Callers use it
  /// to show the right message instead of a generic failure.
  final String? playabilityStatus;

  YtException(this.message, {this.videoId}) : playabilityStatus = null;

  YtException.playability(this.playabilityStatus, String? reason,
      {this.videoId})
      : message = reason == null || reason.isEmpty
            ? 'Not playable ($playabilityStatus)'
            : reason;

  /// True when signing in would likely fix it.
  bool get needsSignIn =>
      playabilityStatus == 'LOGIN_REQUIRED' ||
      playabilityStatus == 'AGE_VERIFICATION_REQUIRED';

  @override
  String toString() => message;
}

/// Isolate worker for [compute] — innertube responses are large.
Map<String, dynamic> _decodeMap(String raw) =>
    jsonDecode(raw) as Map<String, dynamic>;
