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
    try {
      final raw = await db.getKv(_homeCacheKey);
      if (raw != null && raw.isNotEmpty) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        homeShelves = _shelvesFromJson(json['shelves']);
        revision++;
        notifyListeners();
        final at = DateTime.fromMillisecondsSinceEpoch(json['at'] as int? ?? 0);
        if (DateTime.now().difference(at) < _homeCacheTtl) return;
      }
    } catch (_) {}
    if (auth.signedIn) refreshHome();
  }

  /// Fetch the (personalized) home feed. Coalesces concurrent calls.
  Future<void> refreshHome() async {
    if (homeLoading) return;
    homeLoading = true;
    homeError = null;
    notifyListeners();
    try {
      final shelves = await tube.home();
      if (shelves.isNotEmpty) {
        homeShelves = shelves;
        revision++;
        _db?.setKv(
            _homeCacheKey,
            jsonEncode({
              'at': DateTime.now().millisecondsSinceEpoch,
              'shelves': _shelvesToJson(shelves),
            }));
      }
    } catch (e) {
      homeError = e.toString();
    } finally {
      homeLoading = false;
      notifyListeners();
    }
  }

  /// Called after login/logout: drop personalized state and refetch.
  Future<void> onAuthChanged() async {
    homeShelves = const [];
    revision++;
    try {
      await _db?.setKv(_homeCacheKey, '');
    } catch (_) {}
    notifyListeners();
    if (auth.signedIn) await refreshHome();
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

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final s = await resolver.resolve(videoId);
    final req = http.Request('GET', Uri.parse(s.url));
    if (start != null || end != null) {
      req.headers['range'] = 'bytes=${start ?? 0}-${end != null ? end - 1 : ''}';
    }
    final resp = await _client.send(req).timeout(const Duration(seconds: 30));
    if (resp.statusCode >= 400) {
      throw YtException('YT stream HTTP ${resp.statusCode}');
    }
    final total = s.contentLength ?? resp.contentLength;
    return StreamAudioResponse(
      sourceLength: total,
      contentLength: resp.contentLength,
      offset: start ?? 0,
      stream: resp.stream,
      contentType: s.contentType,
    );
  }
}
