import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Listen history + play counts. A "listen" is recorded once a track has
/// actually been heard for a while (not merely skipped past) — the player
/// service calls [onPositionTick] and this decides when it counts.
class HistoryService extends ChangeNotifier {
  static const _maxEntries = 20000;

  /// Seconds of actual playback after which a play counts as a listen.
  /// Overridable from settings via [listenSecondsProvider].
  static const listenAfterSeconds = 20.0;
  int Function()? listenSecondsProvider;

  final List<HistoryEntry> entries = []; // newest first
  final Map<String, int> counts = {}; // track key → listens
  final Map<String, int> firstListen = {}; // track key → epoch ms of first listen
  final Map<String, Track> _byKey = {}; // latest Track snapshot per key

  /// Bumped on any content change — lets views memoize derived structures
  /// (day groups, rankings) instead of recomputing on every rebuild.
  int revision = 0;

  File? _file;
  bool _dirty = false;

  Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    _file = File('${docs.path}${Platform.pathSeparator}history.json');
    try {
      if (await _file!.exists()) {
        // History can hold thousands of entries — decode off the UI thread so
        // startup never drops frames.
        final list =
            await compute(_decodeList, await _file!.readAsString());
        for (final e in list) {
          final entry = HistoryEntry.fromJson(e as Map<String, dynamic>);
          entries.add(entry);
          counts.update(entry.track.key, (n) => n + 1, ifAbsent: () => 1);
          _byKey.putIfAbsent(entry.track.key, () => entry.track);
          // Entries are newest-first, so the last write per key is the oldest.
          firstListen[entry.track.key] = entry.at;
        }
      }
    } catch (_) {
      entries.clear();
      counts.clear();
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
    final want = (listenSecondsProvider?.call() ?? listenAfterSeconds).toDouble();
    final threshold =
        t.duration > 0 ? want.clamp(0, t.duration * 0.5) : want;
    if (_accrued >= threshold) {
      _counted = true;
      _record(t);
    }
  }

  void _record(Track t) {
    final now = DateTime.now().millisecondsSinceEpoch;
    entries.insert(0, HistoryEntry(track: t, at: now));
    if (entries.length > _maxEntries) entries.removeRange(_maxEntries, entries.length);
    counts.update(t.key, (n) => n + 1, ifAbsent: () => 1);
    firstListen.putIfAbsent(t.key, () => now);
    _byKey[t.key] = t;
    _dirty = true;
    revision++;
    notifyListeners();
    _saveSoon();
  }

  Future<void> removeEntry(HistoryEntry e) async {
    entries.remove(e);
    final left = counts.update(e.track.key, (n) => n - 1, ifAbsent: () => 0);
    if (left <= 0) counts.remove(e.track.key);
    _dirty = true;
    revision++;
    notifyListeners();
    _saveSoon();
  }

  Future<void> clear() async {
    entries.clear();
    counts.clear();
    firstListen.clear();
    _byKey.clear();
    _dirty = true;
    revision++;
    notifyListeners();
    _saveSoon();
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

  // ── Persistence (debounced — listens arrive mid-playback) ──────────────────

  bool _saving = false;
  Future<void> _saveSoon() async {
    if (_saving) return;
    _saving = true;
    await Future.delayed(const Duration(seconds: 2));
    _saving = false;
    if (!_dirty) return;
    _dirty = false;
    final f = _file;
    if (f == null) return;
    try {
      await f.writeAsString(jsonEncode(entries.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  /// Flush on app pause so listens aren't lost.
  Future<void> flush() async {
    final f = _file;
    if (f == null || !_dirty) return;
    _dirty = false;
    try {
      await f.writeAsString(jsonEncode(entries.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }
}

List<dynamic> _decodeList(String raw) => jsonDecode(raw) as List;

class HistoryEntry {
  final Track track;
  final int at; // epoch ms

  const HistoryEntry({required this.track, required this.at});

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        track: Track.fromJson((j['track'] ?? {}) as Map<String, dynamic>),
        at: (j['at'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {'track': track.toJson(), 'at': at};
}
