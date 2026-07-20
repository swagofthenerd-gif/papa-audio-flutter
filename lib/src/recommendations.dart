import 'dart:math';

import 'package:flutter/foundation.dart';

import 'history.dart';
import 'local_library.dart';
import 'models.dart';
import 'playlists.dart';
import 'settings.dart';
import 'text_norm.dart';

/// On-device home recommendations. Everything here is derived from data the app
/// already keeps — listen history (counts / firstListen / lastListen / per-listen
/// timestamps), favorites, and the on-phone library — so the home page has real
/// mixes and "made-for-you" shelves without any server or network.
///
/// Shelves are rebuilt off the UI isolate (via [compute]) and memoized by a
/// signature that folds in a *day key*, so the page is stable within a day but
/// reshuffles across days. A listen tick alone never triggers a recompute — the
/// [refresh] call is debounced.
class RecommendationService extends ChangeNotifier {
  List<RecoShelf> shelves = const [];
  int revision = 0;

  String _sig = '';
  bool _computing = false;
  bool _dirty = false;

  static int _dayKey() =>
      DateTime.now().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

  /// Recompute if the inputs (history/library/favorites/settings) or the day
  /// changed. Cheap to call on every home rebuild — it no-ops when the
  /// signature matches, and coalesces overlapping runs.
  Future<void> refresh(
    HistoryService history,
    LocalLibrary library,
    PlaylistsService playlists,
    SettingsService settings,
  ) async {
    final sig = '${history.revision}|${library.revision}|'
        '${playlists.revision}|${settings.revision}|${_dayKey()}';
    if (sig == _sig) return;
    if (_computing) {
      _dirty = true;
      return;
    }
    _sig = sig;
    _computing = true;

    final input = _RecoInput(
      library: [for (final a in library.albums) ...a.tracks],
      historyTracks: history.byKeyTracks,
      entryKeys: [for (final e in history.entries) e.track.key],
      entryAts: [for (final e in history.entries) e.at],
      counts: Map.of(history.counts),
      lastListen: Map.of(history.lastListen),
      firstListen: Map.of(history.firstListen),
      favoriteKeys: {for (final t in playlists.favorites) t.key},
      artistSeparators: settings.artistSeparators,
      genreSeparators: settings.genreSeparators,
      blacklist: settings.splitBlacklist,
      nowMs: DateTime.now().millisecondsSinceEpoch,
      dayKey: _dayKey(),
    );

    try {
      shelves = await compute(_buildShelves, input);
      revision++;
      notifyListeners();
    } catch (_) {
      // Recommendations are best-effort — a failure just leaves the last set.
    } finally {
      _computing = false;
      if (_dirty) {
        _dirty = false;
        // Inputs changed mid-compute; run once more against the latest.
        _sig = '';
        await refresh(history, library, playlists, settings);
      }
    }
  }
}

enum RecoKind { tracks, mixes, artists }

/// A home row. Either a list of [tracks] (rendered as track cards) or a list of
/// [mixes] (rendered as mix cards), decided by [kind].
class RecoShelf {
  final String id;
  final String title;
  final String? kicker; // small eyebrow above the title
  final RecoKind kind;
  final List<Track> tracks;
  final List<RecoMix> mixes;
  final List<RecoArtist> artists;
  const RecoShelf({
    required this.id,
    required this.title,
    this.kicker,
    this.kind = RecoKind.tracks,
    this.tracks = const [],
    this.mixes = const [],
    this.artists = const [],
  });
}

/// A top artist, rendered as a circular tile; tapping plays their catalogue.
class RecoArtist {
  final String name;
  final String? artUri;
  final String? artPath;
  final List<Track> tracks;
  const RecoArtist(
      {required this.name, this.artUri, this.artPath, required this.tracks});
}

/// A generated playlist surfaced as a single card.
class RecoMix {
  final String title;
  final String subtitle;
  final List<Track> tracks;
  const RecoMix(
      {required this.title, required this.subtitle, required this.tracks});
}

// ── Isolate input ─────────────────────────────────────────────────────────────

class _RecoInput {
  final List<Track> library;
  final List<Track> historyTracks; // latest snapshot per played key
  final List<String> entryKeys; // newest-first, parallel to entryAts
  final List<int> entryAts;
  final Map<String, int> counts;
  final Map<String, int> lastListen;
  final Map<String, int> firstListen;
  final Set<String> favoriteKeys;
  final List<String> artistSeparators;
  final List<String> genreSeparators;
  final List<String> blacklist;
  final int nowMs;
  final int dayKey;
  const _RecoInput({
    required this.library,
    required this.historyTracks,
    required this.entryKeys,
    required this.entryAts,
    required this.counts,
    required this.lastListen,
    required this.firstListen,
    required this.favoriteKeys,
    required this.artistSeparators,
    required this.genreSeparators,
    required this.blacklist,
    required this.nowMs,
    required this.dayKey,
  });
}

const _dayMs = Duration.millisecondsPerDay;

// ── Isolate worker ────────────────────────────────────────────────────────────

List<RecoShelf> _buildShelves(_RecoInput inp) {
  final artistSplit =
      TagSplitter(separators: inp.artistSeparators, blacklist: inp.blacklist.toSet());
  final genreSplit =
      TagSplitter(separators: inp.genreSeparators, blacklist: inp.blacklist.toSet());

  // Freshest Track per key: prefer the library copy (richest tags), else the
  // history snapshot.
  final byKey = <String, Track>{};
  for (final t in inp.historyTracks) {
    byKey[t.key] = t;
  }
  for (final t in inp.library) {
    byKey[t.key] = t;
  }

  String primaryArtist(Track t) {
    final parts = artistSplit.split(t.artist);
    return parts.isEmpty ? t.artist : parts.first;
  }

  double recencyDecay(String key, double halfLifeDays) {
    final last = inp.lastListen[key];
    if (last == null) return 0.5; // never played → mild exploration weight
    final days = (inp.nowMs - last) / _dayMs;
    return pow(0.5, days / halfLifeDays).toDouble();
  }

  final shelves = <RecoShelf>[];

  // 1) Forgotten favorites — favorites you haven't heard in a while (or never
  //    since favoriting). Distinct from library-wide Rediscover.
  {
    final cutoff = inp.nowMs - 30 * _dayMs;
    final picks = <Track>[];
    for (final key in inp.favoriteKeys) {
      final last = inp.lastListen[key];
      if (last == null || last < cutoff) {
        final t = byKey[key];
        if (t != null) picks.add(t);
      }
    }
    picks.sort((a, b) =>
        (inp.counts[b.key] ?? 0).compareTo(inp.counts[a.key] ?? 0));
    if (picks.length >= 4) {
      shelves.add(RecoShelf(
        id: 'forgotten_faves',
        kicker: 'FROM YOUR LIKES',
        title: 'Forgotten favorites',
        tracks: picks.take(20).toList(),
      ));
    }
  }

  // 2) Your top mixes — one mix per top artist, seeded by weighted listening.
  {
    final artistWeight = <String, double>{};
    final artistName = <String, String>{}; // norm → display
    for (final entry in inp.counts.entries) {
      final t = byKey[entry.key];
      if (t == null) continue;
      final name = primaryArtist(t);
      final norm = normText(name);
      if (norm.isEmpty) continue;
      artistName[norm] = name;
      artistWeight.update(
          norm, (w) => w + entry.value * recencyDecay(entry.key, 14),
          ifAbsent: () => entry.value * recencyDecay(entry.key, 14));
    }
    final topArtists = artistWeight.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Pool library tracks by primary artist once.
    final libByArtist = <String, List<Track>>{};
    for (final t in inp.library) {
      libByArtist.putIfAbsent(normText(primaryArtist(t)), () => []).add(t);
    }

    final mixes = <RecoMix>[];
    for (final a in topArtists.take(6)) {
      final pool = <Track>[];
      final seen = <String>{};
      void add(Track t) {
        if (seen.add(t.key)) pool.add(t);
      }
      // Played tracks by this artist first, then the rest of their library.
      final lib = libByArtist[a.key] ?? const [];
      final played = lib.where((t) => (inp.counts[t.key] ?? 0) > 0).toList()
        ..sort((x, y) =>
            (inp.counts[y.key] ?? 0).compareTo(inp.counts[x.key] ?? 0));
      for (final t in played) {
        add(t);
      }
      for (final t in lib) {
        add(t);
      }
      if (pool.length < 5) continue;
      final rnd = Random(inp.dayKey * 31 + a.key.hashCode);
      pool.shuffle(rnd);
      mixes.add(RecoMix(
        title: '${artistName[a.key]} Mix',
        subtitle: '${pool.length} songs',
        tracks: pool.take(30).toList(),
      ));
      if (mixes.length >= 5) break;
    }
    if (mixes.length >= 2) {
      shelves.add(RecoShelf(
        id: 'top_mixes',
        kicker: 'MADE FOR YOU',
        title: 'Your top mixes',
        kind: RecoKind.mixes,
        mixes: mixes,
      ));
    }

    // Top artists — circular tiles, most-played first. Reuses the artist
    // weights and library pools computed just above.
    final artists = <RecoArtist>[];
    for (final a in topArtists.take(12)) {
      final lib = libByArtist[a.key] ?? const [];
      if (lib.isEmpty) continue;
      // Representative art = the artist's most-played (else first) track.
      final rep = (lib.where((t) => (inp.counts[t.key] ?? 0) > 0).toList()
            ..sort((x, y) =>
                (inp.counts[y.key] ?? 0).compareTo(inp.counts[x.key] ?? 0)))
          .firstOrNull ??
          lib.first;
      artists.add(RecoArtist(
        name: artistName[a.key] ?? rep.artist,
        artUri: rep.artUri,
        artPath: rep.artPath,
        tracks: lib,
      ));
      if (artists.length >= 10) break;
    }
    if (artists.length >= 3) {
      shelves.add(RecoShelf(
        id: 'top_artists',
        kicker: 'ON REPEAT',
        title: 'Your top artists',
        kind: RecoKind.artists,
        artists: artists,
      ));
    }
  }

  // 3) More from <artist you played recently> — a rotating spotlight seeded by
  //    the last couple days of listening.
  {
    final since = inp.nowMs - 2 * _dayMs;
    final recentArtists = <String, double>{};
    final recentName = <String, String>{};
    for (var i = 0; i < inp.entryKeys.length; i++) {
      if (inp.entryAts[i] < since) break; // newest-first
      final t = byKey[inp.entryKeys[i]];
      if (t == null) continue;
      final name = primaryArtist(t);
      final norm = normText(name);
      if (norm.isEmpty) continue;
      recentName[norm] = name;
      recentArtists.update(norm, (w) => w + 1, ifAbsent: () => 1);
    }
    final ranked = recentArtists.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (ranked.isNotEmpty) {
      // Rotate through the day's top few so the shelf changes daily.
      final pick = ranked[inp.dayKey % min(ranked.length, 4)];
      final pool = inp.library
          .where((t) => normText(primaryArtist(t)) == pick.key)
          .toList()
        ..sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
      if (pool.length >= 4) {
        shelves.add(RecoShelf(
          id: 'more_from_artist',
          kicker: 'BECAUSE YOU LISTENED TO',
          title: 'More from ${recentName[pick.key]}',
          tracks: pool.take(20).toList(),
        ));
      }
    }
  }

  // 4) Daily Mix 1..3 — genre clusters with a little exploration mixed in.
  {
    final byGenre = <String, List<Track>>{};
    for (final entry in inp.counts.entries) {
      final t = byKey[entry.key];
      if (t == null) continue;
      final g = (t.genre == null || t.genre!.isEmpty)
          ? null
          : genreSplit.split(t.genre!).firstOrNull;
      final cluster = normText(g ?? primaryArtist(t));
      if (cluster.isEmpty) continue;
      byGenre.putIfAbsent(cluster, () => []).add(t);
    }
    final libByGenre = <String, List<Track>>{};
    for (final t in inp.library) {
      final g = (t.genre == null || t.genre!.isEmpty)
          ? null
          : genreSplit.split(t.genre!).firstOrNull;
      final cluster = normText(g ?? primaryArtist(t));
      if (cluster.isEmpty) continue;
      libByGenre.putIfAbsent(cluster, () => []).add(t);
    }
    final clusters = byGenre.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    final mixes = <RecoMix>[];
    for (var i = 0; i < clusters.length && mixes.length < 3; i++) {
      final c = clusters[i];
      final scored = c.value.toList()
        ..sort((x, y) {
          double s(Track t) =>
              (log(1 + (inp.counts[t.key] ?? 0))) * recencyDecay(t.key, 21) +
              (inp.favoriteKeys.contains(t.key) ? 0.5 : 0);
          return s(y).compareTo(s(x));
        });
      final pool = <Track>[];
      final seen = <String>{};
      for (final t in scored) {
        if (seen.add(t.key)) pool.add(t);
      }
      // ~20% exploration: unplayed library tracks from the same cluster.
      for (final t in (libByGenre[c.key] ?? const [])) {
        if ((inp.counts[t.key] ?? 0) == 0 && seen.add(t.key)) pool.add(t);
        if (pool.length >= 40) break;
      }
      if (pool.length < 5) continue;
      pool.shuffle(Random(inp.dayKey * 17 + c.key.hashCode));
      mixes.add(RecoMix(
        title: 'Daily Mix ${mixes.length + 1}',
        subtitle: pool
            .map((t) => t.artist)
            .toSet()
            .take(3)
            .join(', '),
        tracks: pool.take(30).toList(),
      ));
    }
    if (mixes.isNotEmpty) {
      shelves.add(RecoShelf(
        id: 'daily_mix',
        kicker: 'MADE FOR YOU',
        title: 'Daily mixes',
        kind: RecoKind.mixes,
        mixes: mixes,
      ));
    }
  }

  // 5) Time-of-day rotation — what you tend to play around this hour.
  {
    final hour = DateTime.fromMillisecondsSinceEpoch(inp.nowMs).hour;
    int daypart(int h) => h < 6 ? 0 : (h < 12 ? 1 : (h < 18 ? 2 : 3));
    final want = daypart(hour);
    final tally = <String, int>{};
    for (var i = 0; i < inp.entryKeys.length; i++) {
      final h = DateTime.fromMillisecondsSinceEpoch(inp.entryAts[i]).hour;
      if (daypart(h) != want) continue;
      tally.update(inp.entryKeys[i], (n) => n + 1, ifAbsent: () => 1);
    }
    final ranked = tally.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final tracks = <Track>[];
    for (final e in ranked) {
      final t = byKey[e.key];
      if (t != null) tracks.add(t);
      if (tracks.length >= 20) break;
    }
    if (tracks.length >= 6) {
      const labels = [
        'Late-night rotation',
        'Morning rotation',
        'Afternoon rotation',
        'Evening rotation',
      ];
      shelves.add(RecoShelf(
        id: 'time_of_day',
        kicker: 'RIGHT NOW',
        title: labels[want],
        tracks: tracks,
      ));
    }
  }

  // 6) From <year> — a played-year the app has mass in, rotated daily.
  {
    final byYear = <int, int>{}; // year → play mass
    for (final entry in inp.counts.entries) {
      final t = byKey[entry.key];
      if (t == null || t.year == 0) continue;
      byYear.update(t.year, (n) => n + entry.value, ifAbsent: () => entry.value);
    }
    final years = byYear.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (years.isNotEmpty) {
      final year = years[inp.dayKey % min(years.length, 3)].key;
      final pool = inp.library.where((t) => t.year == year).toList()
        ..sort((a, b) =>
            (inp.counts[b.key] ?? 0).compareTo(inp.counts[a.key] ?? 0));
      if (pool.length >= 5) {
        pool.shuffle(Random(inp.dayKey * 13 + year));
        shelves.add(RecoShelf(
          id: 'from_year',
          kicker: 'TIME MACHINE',
          title: 'From $year',
          tracks: pool.take(20).toList(),
        ));
      }
    }
  }

  // 7) New in library, unheard — recently added tracks you haven't played yet.
  {
    final unheard = inp.library
        .where((t) => (inp.counts[t.key] ?? 0) == 0 && t.dateAdded > 0)
        .toList()
      ..sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
    if (unheard.length >= 5) {
      shelves.add(RecoShelf(
        id: 'new_unheard',
        kicker: 'FRESH',
        title: 'New in your library',
        tracks: unheard.take(20).toList(),
      ));
    }
  }

  return shelves;
}
