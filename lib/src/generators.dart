import 'dart:math';
import 'models.dart';

/// Track recommendation / generation engine.
/// Approximates Namida's "NamidaGenerator" algorithms.
class GeneratorsController {
  GeneratorsController._();
  static final GeneratorsController inst = GeneratorsController._();

  final Random _rng = Random();

  /// Generate [count] random tracks from [pool].
  List<Track> randomPicks(List<Track> pool, {int count = 20}) {
    if (pool.length <= count) return List.from(pool)..shuffle(_rng);
    final indices = <int>{};
    while (indices.length < count) {
      indices.add(_rng.nextInt(pool.length));
    }
    return indices.map((i) => pool[i]).toList();
  }

  /// Rediscover: tracks not played in [minDays] days.
  List<Track> rediscover(List<Track> allTracks, Map<String, DateTime> lastPlayed, {int minDays = 30, int count = 20}) {
    final cutoff = DateTime.now().subtract(Duration(days: minDays));
    final candidates = allTracks.where((t) {
      final lp = lastPlayed[t.path];
      return lp == null || lp.isBefore(cutoff);
    }).toList();
    candidates.shuffle(_rng);
    return candidates.take(count).toList();
  }

  /// Favorites: top [count] most-played tracks.
  List<Track> favorites(List<Track> allTracks, Map<String, int> playCounts, {int count = 20}) {
    final sorted = List<Track>.from(allTracks);
    sorted.sort((a, b) => (playCounts[b.path] ?? 0).compareTo(playCounts[a.path] ?? 0));
    return sorted.take(count).toList();
  }

  /// Discover: tracks similar to what user likes, using basic heuristics.
  List<Track> discover(List<Track> allTracks, Map<String, int> playCounts, {int count = 20}) {
    // Find top artists the user likes
    final artistPlays = <String, int>{};
    for (final t in allTracks) {
      final plays = playCounts[t.path] ?? 0;
      if (plays > 0) {
        for (final a in t.artist.split(';')) {
          artistPlays[a.trim()] = (artistPlays[a.trim()] ?? 0) + plays;
        }
      }
    }
    final topArtists = artistPlays.entries
        .where((e) => e.value >= 2)
        .map((e) => e.key)
        .toSet();

    // Tracks by top artists that haven't been played much
    final candidates = allTracks.where((t) {
      if ((playCounts[t.path] ?? 0) >= 3) return false; // Already well-known
      final trackArtists = t.artist.split(';').map((a) => a.trim()).toSet();
      return trackArtists.any((a) => topArtists.contains(a));
    }).toList();

    candidates.shuffle(_rng);
    if (candidates.length >= count) return candidates.take(count).toList();

    // Fill remaining with random
    final remaining = allTracks.where((t) => !candidates.contains(t)).toList()..shuffle(_rng);
    return [...candidates, ...remaining.take(count - candidates.length)];
  }

  /// "Smort" weighted mix: 40% recent favorites, 30% rediscover, 20% random, 10% new
  List<Track> smortMix(
    List<Track> allTracks,
    Map<String, int> playCounts,
    Map<String, DateTime> lastPlayed,
    {int count = 20}
  ) {
    final fav = favorites(allTracks, playCounts, count: (count * 0.4).round());
    final redis = rediscover(allTracks, lastPlayed, count: (count * 0.3).round());
    final rand = randomPicks(allTracks, count: (count * 0.2).round());
    final disc = discover(allTracks, playCounts, count: (count * 0.1).round());

    final result = <Track>[...fav, ...redis, ...rand, ...disc];
    result.shuffle(_rng);
    return result.take(count).toList();
  }
}
