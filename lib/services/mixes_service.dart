import 'dart:math';

import 'package:flutter/foundation.dart';

import '../src/history.dart';
import '../src/models.dart';
import '../src/playlists.dart';

/// Generates smart mixes from the local library + listening history.
///
/// Uses [HistoryService] for play counts / recency and [PlaylistsService] for
/// favorites. Callers provide the full track pool (e.g. from [LocalLibrary])
/// and play-out via [PlayerService].
class MixesService extends ChangeNotifier {
  final HistoryService _history;
  final PlaylistsService _playlists;
  final List<Track> Function() _allTracks;

  MixesService({
    required HistoryService history,
    required PlaylistsService playlists,
    required List<Track> Function() allTracks,
  })  : _history = history,
        _playlists = playlists,
        _allTracks = allTracks;

  // ── Mix generators ──────────────────────────────────────────────────────────

  /// Tracks you haven't heard recently (or ever), weighted toward higher-rated
  /// (favorited + high play-count) material so the mix feels curated.
  List<Track> generateDiscoverMix({int count = 20}) {
    final pool = _allTracks();
    if (pool.isEmpty) return [];

    final now = DateTime.now().millisecondsSinceEpoch;
    const recentCutoff = 7 * 24 * 60 * 60 * 1000; // 7 days in ms
    final rng = Random();

    // Score each track: higher = more interesting to discover.
    final scored = <(Track, double)>[];
    for (final t in pool) {
      final last = _history.lastListen[t.key];
      final plays = _history.counts[t.key] ?? 0;
      final fav = _playlists.isFavorite(t) ? 1.0 : 0.0;

      // Skip very recently played tracks (within 7 days).
      if (last != null && (now - last) < recentCutoff) continue;

      // Weight: favorites + moderate play count = "good but not overplayed".
      double score = fav * 3.0 + (plays.clamp(0, 20) * 0.2);
      // Add a little jitter so the same pool doesn't return identical order.
      score += rng.nextDouble() * 1.5;
      scored.add((t, score));
    }

    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(count).map((e) => e.$1).toList();
  }

  /// Most-played tracks blended with recently played tracks — the stuff you
  /// clearly love.
  List<Track> generateFavoritesMix({int count = 20}) {
    final pool = _allTracks();
    if (pool.isEmpty) return [];

    final favKeys = _playlists.favorites.map((t) => t.key).toSet();
    final rng = Random();

    final scored = <(Track, double)>[];
    for (final t in pool) {
      final plays = _history.counts[t.key] ?? 0;
      final last = _history.lastListen[t.key];
      final isFav = favKeys.contains(t.key) ? 1.0 : 0.0;

      // Recency bonus: played within 30 days → higher score.
      double recencyBonus = 0;
      if (last != null) {
        final daysAgo =
            (DateTime.now().millisecondsSinceEpoch - last) / (24 * 60 * 60 * 1000);
        if (daysAgo < 30) recencyBonus = (30 - daysAgo) / 30 * 2.0;
      }

      double score = isFav * 4.0 + plays * 0.5 + recencyBonus + rng.nextDouble();
      scored.add((t, score));
    }

    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(count).map((e) => e.$1).toList();
  }

  /// Tracks you used to listen to but haven't touched in a long time — the
  /// "hidden gems" that fell out of rotation.
  List<Track> generateRediscoverMix({int count = 20}) {
    // Reuse the history service's own rediscover logic, then pad with
    // additional low-recency, medium-count tracks from the full pool.
    final fromHistory = _history.rediscover(olderThanDays: 30, limit: count);
    if (fromHistory.length >= count) return fromHistory.take(count).toList();

    final have = fromHistory.map((t) => t.key).toSet();
    final pool = _allTracks();
    final now = DateTime.now().millisecondsSinceEpoch;
    const oldThreshold = 30 * 24 * 60 * 60 * 1000; // 30 days

    final candidates = <(Track, int)>[];
    for (final t in pool) {
      if (have.contains(t.key)) continue;
      final last = _history.lastListen[t.key];
      // Only tracks that were actually played before but not recently.
      if (last == null || (now - last) < oldThreshold) continue;
      final plays = _history.counts[t.key] ?? 0;
      candidates.add((t, plays));
    }

    candidates.sort((a, b) => b.$2.compareTo(a.$2));
    final extra = candidates.take(count - fromHistory.length).map((e) => e.$1);

    return [...fromHistory, ...extra];
  }

  /// Pure shuffle — zero weighting. Quick and surprising.
  List<Track> generateRandomMix({int count = 20}) {
    final pool = List<Track>.of(_allTracks());
    if (pool.isEmpty) return [];
    pool.shuffle(Random());
    return pool.take(count).toList();
  }
}
