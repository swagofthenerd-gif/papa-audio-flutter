import 'dart:math';

import 'history.dart';
import 'models.dart';

/// Smart discovery and rediscovery engine.
///
/// Generates weighted mixes inspired by Namida's "Smort Tracks" algorithm:
/// balances familiarity (tracks you know and love) with discovery
/// (tracks you haven't heard recently or at all).
class SmortTracksService {
  final HistoryService _history;

  SmortTracksService(this._history);

  /// Generate a smart mix of [count] tracks from the available pool.
  ///
  /// The algorithm:
  /// 1. 40% — Familiar favorites (most played, weighted by play count)
  /// 2. 30% — Rediscovery (tracks not heard in 14+ days)
  /// 3. 20% — Discovery (tracks never played)
  /// 4. 10% — Wild cards (random, but preferred recently added)
  Future<List<Track>> generateMix(
    List<Track> pool, {
    int count = 30,
    Random? rng,
  }) async {
    final random = rng ?? Random();
    if (pool.isEmpty) return [];

    // Get history data
    final playCounts = await _history.getAllPlayCounts();
    final lastPlayed = await _history.getLastPlayed();

    // Categorize the pool
    final familiar = <Track>[];
    final rediscover = <Track>[];
    final discovery = <Track>[];
    final recent = <Track>[];

    final now = DateTime.now();
    final twoWeeksAgo = now.subtract(const Duration(days: 14));
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));

    for (final track in pool) {
      final key = track.path;
      final count = playCounts[key] ?? 0;
      final last = lastPlayed[key];

      if (count >= 3) {
        familiar.add(track);
      }
      if (last != null && last.isBefore(twoWeeksAgo)) {
        rediscover.add(track);
      }
      if (count == 0) {
        discovery.add(track);
      }
      if (last != null && last.isAfter(thirtyDaysAgo)) {
        recent.add(track);
      }
    }

    // Weighted selection
    final result = <Track>{};

    // 40% Familiar (weighted by play count)
    final familiarCount = (count * 0.4).round();
    for (var i = 0; i < familiarCount && familiar.isNotEmpty; i++) {
      result.add(_weightedPick(familiar, (t) {
        final c = playCounts[t.path] ?? 1;
        return c * c.toDouble(); // Square for stronger weighting
      }, random));
    }

    // 30% Rediscovery
    final rediscoverCount = (count * 0.3).round();
    final redisPool =
        rediscover.where((t) => !result.contains(t)).toList();
    for (var i = 0;
        i < rediscoverCount && i < redisPool.length;
        i++) {
      result.add(redisPool[random.nextInt(redisPool.length)]);
    }

    // 20% Discovery
    final discoveryCount = (count * 0.2).round();
    final discPool =
        discovery.where((t) => !result.contains(t)).toList();
    for (var i = 0;
        i < discoveryCount && i < discPool.length;
        i++) {
      result.add(discPool[random.nextInt(discPool.length)]);
    }

    // 10% Recent wild cards
    final wildCount = (count * 0.1).round();
    final wildPool = recent.where((t) => !result.contains(t)).toList();
    if (wildPool.isNotEmpty) {
      for (var i = 0;
          i < wildCount && i < wildPool.length;
          i++) {
        result.add(wildPool[random.nextInt(wildPool.length)]);
      }
    }

    // Fill remaining slots from pool
    final remaining = count - result.length;
    if (remaining > 0) {
      final fillPool = pool.where((t) => !result.contains(t)).toList();
      fillPool.shuffle(random);
      result.addAll(fillPool.take(remaining));
    }

    final mix = result.toList();
    mix.shuffle(random);
    return mix.take(count).toList();
  }

  /// Generate a "Rediscover" mix — tracks you haven't heard in a while.
  Future<List<Track>> generateRediscoverMix(
    List<Track> pool, {
    int count = 20,
    int minDaysSincePlayed = 30,
  }) async {
    if (pool.isEmpty) return [];
    final lastPlayed = await _history.getLastPlayed();
    final cutoff = DateTime.now().subtract(Duration(days: minDaysSincePlayed));

    final candidates = pool.where((t) {
      final last = lastPlayed[t.path];
      return last == null || last.isBefore(cutoff);
    }).toList();

    candidates.shuffle();
    return candidates.take(count).toList();
  }

  /// Generate a "Favorites" mix — your most played tracks.
  Future<List<Track>> generateFavoritesMix(
    List<Track> pool, {
    int count = 20,
  }) async {
    if (pool.isEmpty) return [];
    final playCounts = await _history.getAllPlayCounts();
    final sorted = List<Track>.from(pool)
      ..sort((a, b) {
        final ca = playCounts[a.path] ?? 0;
        final cb = playCounts[b.path] ?? 0;
        return cb.compareTo(ca);
      });
    return sorted.take(count).toList();
  }

  /// Weighted random pick where higher weight = more likely to be chosen.
  T _weightedPick<T>(
      List<T> items, double Function(T) weightFn, Random random) {
    final weights = items.map(weightFn).toList();
    final total = weights.fold<double>(0, (a, b) => a + b);
    var roll = random.nextDouble() * total;
    for (var i = 0; i < items.length; i++) {
      roll -= weights[i];
      if (roll <= 0) return items[i];
    }
    return items.last;
  }
}
