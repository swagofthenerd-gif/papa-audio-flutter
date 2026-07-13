import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'db.dart';
import 'models.dart';

/// Listen history + play counts, backed by SQLite. A "listen" is recorded once
/// a track has actually been heard for a while (not merely skipped past) — the
/// player service calls [onPositionTick] and this decides when it counts.
///
/// Recent entries stay in memory for instant day-grouping in the UI; every
/// mutation is a single incremental DB write (never a full rewrite).
class HistoryService extends ChangeNotifier {
  static const _memoryCap = 20000;

  /// Seconds of actual playback after which a play counts as a listen.
  /// Overridable from settings via [listenSecondsProvider].
  static const listenAfterSeconds = 20.0;
  int Function()? listenSecondsProvider;

  /// When set, wins over [listenSecondsProvider]: returns the full threshold
  /// in seconds for a given track (settings decide seconds vs percent mode).
  double Function(Track)? thresholdProvider;

  final List<HistoryEntry> entries = []; // newest first (recent window)
  final Map<String, int> counts = {}; // track key → listens (all time)
  final Map<String, int> firstListen = {}; // track key → epoch ms of first listen
  final Map<String, int> lastListen = {}; // track key → epoch ms of latest listen
  final Map<String, Track> _byKey = {}; // latest Track snapshot per key

  /// Bumped on any content change — lets views memoize derived structures
  /// (day groups, rankings) instead of recomputing on every rebuild.
  int revision = 0;

  AppDatabase? _db;

  Future<void> init(AppDatabase db) async {
    _db = db;
    try {
      // Recent window for the UI + all-time aggregates via SQL.
      final rows = await db.db.query('history',
          orderBy: 'id DESC', limit: _memoryCap);
      final agg = await db.db.rawQuery(
          'SELECT track_key, COUNT(*) c, MIN(at) first_at, MAX(at) last_at '
          'FROM history GROUP BY track_key');
      final snaps = await db.db.rawQuery(
          'SELECT h.track_key, h.track_json FROM history h '
          'INNER JOIN (SELECT track_key k, MAX(id) m FROM history GROUP BY track_key) x '
          'ON h.id = x.m');
      // Thousands of jsonDecode+Track builds — off the UI isolate.
      final built = await compute(_buildHistoryState, (rows, snaps));
      entries.addAll(built.$1);
      _byKey.addAll(built.$2);
      for (final r in agg) {
        counts[r['track_key'] as String] = r['c'] as int;
        firstListen[r['track_key'] as String] = r['first_at'] as int;
        lastListen[r['track_key'] as String] = r['last_at'] as int;
      }
    } catch (_) {
      entries.clear();
      counts.clear();
      firstListen.clear();
      lastListen.clear();
    }
    revision++;
    notifyListeners();
  }

  // ── Recording ───────────────────────────────────────────────────────────────

  String? _pendingKey; // track currently accruing playback time
  double _accrued = 0;
  bool _counted = false;

  /// Called by the player once per second of *playing* time on the current
  /// track. Switching tracks resets accrual, so skipping doesn't count.
  void onPositionTick(Track t) {
    if (_pendingKey != t.key) {
      _pendingKey = t.key;
      _accrued = 0;
      _counted = false;
    }
    if (_counted) return;
    _accrued += 1;
    final double threshold;
    if (thresholdProvider != null) {
      threshold = thresholdProvider!(t);
    } else {
      final want =
          (listenSecondsProvider?.call() ?? listenAfterSeconds).toDouble();
      threshold = t.duration > 0 ? want.clamp(0, t.duration * 0.5) : want;
    }
    if (_accrued >= threshold) {
      _counted = true;
      _record(t);
    }
  }

  Future<void> _record(Track t) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    counts.update(t.key, (n) => n + 1, ifAbsent: () => 1);
    firstListen.putIfAbsent(t.key, () => now);
    lastListen[t.key] = now;
    _byKey[t.key] = t;
    int? dbId;
    try {
      dbId = await _db?.db.insert('history', {
        'at': now,
        'track_key': t.key,
        'track_json': jsonEncode(t.toJson()),
      });
    } catch (_) {}
    entries.insert(0, HistoryEntry(dbId: dbId, track: t, at: now));
    if (entries.length > _memoryCap) {
      entries.removeRange(_memoryCap, entries.length);
    }
    revision++;
    notifyListeners();
  }

  Future<void> removeEntry(HistoryEntry e) async {
    entries.remove(e);
    final left = counts.update(e.track.key, (n) => n - 1, ifAbsent: () => 0);
    if (left <= 0) counts.remove(e.track.key);
    if (e.dbId != null) {
      try {
        await _db?.db.delete('history', where: 'id = ?', whereArgs: [e.dbId]);
      } catch (_) {}
    }
    revision++;
    notifyListeners();
  }

  Future<void> clear() async {
    entries.clear();
    counts.clear();
    firstListen.clear();
    lastListen.clear();
    _byKey.clear();
    try {
      await _db?.db.delete('history');
    } catch (_) {}
    revision++;
    notifyListeners();
  }

  // ── Views ───────────────────────────────────────────────────────────────────

  int listensOf(Track t) => counts[t.key] ?? 0;

  /// Distinct tracks ordered by listen count (desc). [since] limits to
  /// listens after that time (for day/week/month/all-time ranges).
  List<(Track, int)> mostPlayed({DateTime? since, int limit = 100}) {
    final Map<String, int> tally;
    if (since == null) {
      tally = counts;
    } else {
      final cutoff = since.millisecondsSinceEpoch;
      tally = {};
      for (final e in entries) {
        if (e.at < cutoff) break; // entries are newest-first
        tally.update(e.track.key, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    final sorted = tally.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final e in sorted.take(limit))
        if (_byKey[e.key] != null) (_byKey[e.key]!, e.value),
    ];
  }

  /// "Rediscover": tracks you used to listen to but haven't touched lately —
  /// last listen older than [olderThanDays], ordered by all-time count desc.
  List<Track> rediscover({int olderThanDays = 30, int limit = 20}) {
    final cutoff = DateTime.now()
        .subtract(Duration(days: olderThanDays))
        .millisecondsSinceEpoch;
    final keyed = <(int, Track)>[
      for (final e in lastListen.entries)
        if (e.value < cutoff && _byKey[e.key] != null)
          (counts[e.key] ?? 0, _byKey[e.key]!)
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final k in keyed.take(limit)) k.$2];
  }

  /// History as distinct recent tracks (dedup keeps the newest occurrence).
  List<Track> recentTracks({int limit = 100}) {
    final seen = <String>{};
    final out = <Track>[];
    for (final e in entries) {
      if (seen.add(e.track.key)) {
        out.add(e.track);
        if (out.length >= limit) break;
      }
    }
    return out;
  }

  /// Writes are incremental now; kept for the app-lifecycle hook's benefit.
  Future<void> flush() async {}
}

/// Isolate worker: decode history rows + latest-snapshot rows into objects.
(List<HistoryEntry>, Map<String, Track>) _buildHistoryState(
    (List<Map<String, Object?>>, List<Map<String, Object?>>) input) {
  final (rows, snaps) = input;
  final entries = <HistoryEntry>[
    for (final r in rows)
      HistoryEntry(
        dbId: r['id'] as int,
        track: Track.fromJson(
            jsonDecode(r['track_json'] as String) as Map<String, dynamic>),
        at: r['at'] as int,
      )
  ];
  final byKey = <String, Track>{
    for (final r in snaps)
      r['track_key'] as String: Track.fromJson(
          jsonDecode(r['track_json'] as String) as Map<String, dynamic>)
  };
  return (entries, byKey);
}

class HistoryEntry {
  final int? dbId;
  final Track track;
  final int at; // epoch ms

  const HistoryEntry({this.dbId, required this.track, required this.at});
}
