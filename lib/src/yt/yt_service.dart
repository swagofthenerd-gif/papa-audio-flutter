import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

import '../db.dart';
import 'innertube.dart';
import 'yt_auth.dart';
import 'yt_models.dart';

/// High-level YouTube Music state: the personalized home feed, explore
/// surfaces, library imports — cached, revisioned, and refreshed in the
/// background so the UI always has something to paint instantly.
class YtService extends ChangeNotifier {
  final YtAuth auth;
  late final Innertube tube = Innertube(auth);
  late final YtStreamResolver resolver = YtStreamResolver(tube);

  YtService(this.auth);

  AppDatabase? _db;
  static const _homeCacheKey = 'yt_home_cache';
  static const _homeCacheTtl = Duration(hours: 2);

  List<YtShelf> homeShelves = const [];
  bool homeLoading = false;
  String? homeError;
  int revision = 0;

  Future<void> init(AppDatabase db) async {
    _db = db;
    // Warm start: paint last session's feed instantly, refresh behind it.
    // A cache written under a different auth state is someone else's feed —
    // never paint it (that's the "stale anonymous home after sign-in" bug).
    try {
      final raw = await db.getKv(_homeCacheKey);
      if (raw != null && raw.isNotEmpty) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final cachedSignedIn = json['signedIn'] == true;
        if (cachedSignedIn == auth.signedIn) {
          homeShelves = _shelvesFromJson(json['shelves']);
          revision++;
          notifyListeners();
          final at =
              DateTime.fromMillisecondsSinceEpoch(json['at'] as int? ?? 0);
          if (DateTime.now().difference(at) < _homeCacheTtl) return;
        }
      }
    } catch (_) {}
    refreshHome();
  }

  /// Fetch the (personalized) home feed. Coalesces concurrent calls.
  Future<void> refreshHome() async {
    if (homeLoading) return;
    homeLoading = true;
    homeError = null;
    notifyListeners();
    try {
      final shelves = await tube.home();
      debugPrint('[yt] home refresh: signedIn=${auth.signedIn} '
          'parsed=${shelves.length} shelves');
      if (shelves.isNotEmpty) {
        homeShelves = shelves;
        revision++;
        _db?.setKv(
            _homeCacheKey,
            jsonEncode({
              'at': DateTime.now().millisecondsSinceEpoch,
              'signedIn': auth.signedIn,
              'shelves': _shelvesToJson(shelves),
            }));
      } else if (homeShelves.isEmpty) {
        // Response parsed to nothing and there's no feed on screen — surface
        // it instead of leaving a silent blank (never overwrite a good feed).
        homeError = 'Feed returned no recognizable content';
      }
    } catch (e) {
      debugPrint('[yt] home refresh failed: $e');
      homeError = e.toString();
    } finally {
      homeLoading = false;
      notifyListeners();
    }
  }

  /// Called after login/logout: invalidate the cache and refetch. The old
  /// shelves stay on screen under a loading state until the new feed lands —
  /// clearing them first caused a blank flash.
  Future<void> onAuthChanged() async {
    try {
      await _db?.setKv(_homeCacheKey, '');
    } catch (_) {}
    homeLoading = false; // let refreshHome() through even if one is in flight
    await refreshHome(); // anonymous home also returns shelves on sign-out
  }

  // ── Shelf (de)serialization for the warm-start cache ──────────────────────

  static List<Map<String, dynamic>> _shelvesToJson(List<YtShelf> shelves) => [
        for (final s in shelves)
          {
            'title': s.title,
            'items': [
              for (final i in s.items)
                {
                  'kind': i.kind.index,
                  'videoId': i.videoId,
                  'browseId': i.browseId,
                  'playlistId': i.playlistId,
                  'title': i.title,
                  'subtitle': i.subtitle,
                  'thumbnail': i.thumbnail,
                }
            ],
          }
      ];

  static List<YtShelf> _shelvesFromJson(dynamic json) {
    if (json is! List) return const [];
    return [
      for (final s in json.whereType<Map>())
        YtShelf(
          title: (s['title'] ?? '').toString(),
          items: [
            for (final i in (s['items'] as List? ?? []).whereType<Map>())
              YtMusicItem(
                kind: YtItemKind.values[
                    ((i['kind'] as num?) ?? 0).toInt().clamp(
                        0, YtItemKind.values.length - 1)],
                videoId: i['videoId']?.toString(),
                browseId: i['browseId']?.toString(),
                playlistId: i['playlistId']?.toString(),
                title: (i['title'] ?? '').toString(),
                subtitle: (i['subtitle'] ?? '').toString(),
                thumbnail: i['thumbnail']?.toString(),
              )
          ],
        )
    ];
  }

  @override
  void dispose() {
    tube.dispose();
    super.dispose();
  }
}

/// Resolves and caches direct audio-stream URLs per video. Stream URLs expire
/// after a few hours; [resolve] transparently re-fetches stale ones. Coalesces
/// concurrent requests for the same id.
class YtStreamResolver {
  final Innertube tube;
  YtStreamResolver(this.tube);

  static const _cap = 128; // bounded LRU — hours of playback can't grow this
  final Map<String, Future<YtStream>> _inFlight = {};
  final Map<String, YtStream> _cache = {}; // insertion-ordered => LRU

  Future<YtStream> resolve(String videoId) {
    final hit = _cache.remove(videoId);
    if (hit != null && hit.fresh) {
      _cache[videoId] = hit; // re-insert = mark most-recently-used
      return Future.value(hit);
    }
    final pending = _inFlight[videoId];
    if (pending != null) return pending;
    final future = tube.playerStream(videoId).then((s) {
      _cache[videoId] = s;
      while (_cache.length > _cap) {
        _cache.remove(_cache.keys.first); // evict least-recently-used
      }
      return s;
    }).whenComplete(() => _inFlight.remove(videoId));
    _inFlight[videoId] = future;
    return future;
  }

  /// Drop a cached stream so the next resolve re-fetches a fresh URL. Used when
  /// playback of a track fails — most failures are simply expired URLs.
  void invalidate(String videoId) {
    _cache.remove(videoId);
    _inFlight.remove(videoId);
  }

  /// Warm the cache for upcoming queue entries so track changes are instant.
  void prefetch(Iterable<String> videoIds) {
    for (final id in videoIds.take(3)) {
      final hit = _cache[id];
      if (hit == null || !hit.fresh) {
        // Fire-and-forget; failures will surface (with retry) at play time.
        resolve(id).then((_) {}, onError: (_) {});
      }
    }
  }
}

/// A just_audio source that resolves its stream URL on first byte request and
/// proxies ranged reads. This is what makes a 30-track mix enqueue instantly:
/// nothing resolves until the player actually reaches the track (plus whatever
/// [YtStreamResolver.prefetch] warmed).
class YtLazyAudioSource extends StreamAudioSource {
  final String videoId;
  final YtStreamResolver resolver;
  final http.Client _client = http.Client();

  YtLazyAudioSource(this.videoId, this.resolver, {super.tag});

  // googlevideo rejects unranged and over-large range requests on some client
  // URLs (403 above ~1–2 MB observed on IOS-minted URLs), so everything is
  // fetched as sequential bounded chunks and stitched into one stream.
  static const chunkBytes = 1024 * 1024;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final s = await resolver.resolve(videoId);
    final from = start ?? 0;
    // First chunk fetched eagerly: it validates the URL (errors surface here,
    // not mid-stream) and its content-range reveals the total length. Ranges
    // must never run past EOF — googlevideo rejects out-of-bounds requests —
    // so cap by every length we know.
    final first = await _fetchChunk(s, from, end ?? s.contentLength);
    final total = s.contentLength ?? first.total;
    final endExcl = end ?? total;
    return StreamAudioResponse(
      sourceLength: total,
      contentLength: endExcl != null ? endExcl - from : null,
      offset: from,
      stream: _chunks(s, first, from, endExcl),
      contentType: s.contentType,
    );
  }

  Future<_Chunk> _fetchChunk(YtStream s, int from, int? endExcl) async {
    var to = from + chunkBytes; // exclusive
    if (endExcl != null && endExcl < to) to = endExcl;
    final req = http.Request('GET', Uri.parse(s.url));
    req.headers['user-agent'] = s.userAgent;
    req.headers['range'] = 'bytes=$from-${to - 1}';
    final resp = await _client.send(req).timeout(const Duration(seconds: 30));
    if (resp.statusCode >= 400) {
      throw YtException('YT stream HTTP ${resp.statusCode}');
    }
    // "bytes 0-1048575/3143133" → total size after the slash.
    int? total;
    final cr = resp.headers['content-range'];
    final slash = cr?.lastIndexOf('/') ?? -1;
    if (cr != null && slash >= 0) {
      total = int.tryParse(cr.substring(slash + 1));
    }
    return _Chunk(resp.stream, to, total);
  }

  Stream<List<int>> _chunks(
      YtStream s, _Chunk first, int from, int? endExcl) async* {
    var chunk = first;
    var pos = from;
    while (true) {
      yield* chunk.body;
      pos = chunk.nextFrom;
      final limit = endExcl ?? chunk.total ?? s.contentLength;
      if (limit != null && pos >= limit) return;
      try {
        chunk = await _fetchChunk(s, pos, limit);
      } catch (e) {
        debugPrint('[yt] chunk $videoId @$pos/$limit failed: $e');
        rethrow;
      }
    }
  }
}

class _Chunk {
  final http.ByteStream body;
  final int nextFrom; // exclusive end of this chunk = start of the next
  final int? total; // full resource size from content-range, when reported
  _Chunk(this.body, this.nextFrom, this.total);
}
