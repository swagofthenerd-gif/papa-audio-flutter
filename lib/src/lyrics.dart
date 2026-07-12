import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import 'db.dart';
import 'models.dart';

/// One timestamped lyric line from an LRC document.
class LrcLine {
  final Duration at;
  final String text;
  const LrcLine(this.at, this.text);
}

/// Parses standard LRC: `[mm:ss.xx] text`, including multiple timestamps per
/// line and hour-long tracks (`[hh:mm:ss]` is rare but tolerated via minutes
/// overflow). Metadata tags like `[ar:...]` are skipped.
List<LrcLine> parseLrc(String raw) {
  final out = <LrcLine>[];
  final stampRe = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  for (final line in raw.split(RegExp(r'\r?\n'))) {
    final stamps = stampRe.allMatches(line).toList();
    if (stamps.isEmpty) continue;
    final text = line.substring(stamps.last.end).trim();
    for (final m in stamps) {
      final min = int.parse(m.group(1)!);
      final sec = int.parse(m.group(2)!);
      final fracRaw = m.group(3) ?? '0';
      // ".5" = 500ms, ".55" = 550ms, ".555" = 555ms.
      final ms = (int.parse(fracRaw) * (1000 / _pow10(fracRaw.length))).round();
      out.add(LrcLine(
          Duration(minutes: min, seconds: sec, milliseconds: ms), text));
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

int _pow10(int n) => n == 1 ? 10 : n == 2 ? 100 : 1000;

/// Index of the line active at [position] (last line whose stamp has passed),
/// or -1 before the first line. Binary search — called every position tick.
int lrcLineIndexAt(List<LrcLine> lines, Duration position) {
  var lo = 0, hi = lines.length - 1, ans = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (lines[mid].at <= position) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}

/// Lyrics for one track: synced lines when available, else plain text.
class Lyrics {
  final List<LrcLine> synced;
  final String plain;
  const Lyrics({required this.synced, required this.plain});
  bool get hasSynced => synced.isNotEmpty;
  bool get isEmpty => synced.isEmpty && plain.trim().isEmpty;
}

/// Fetches lyrics from LRCLIB (lrclib.net — an open lyrics database) and
/// caches results in SQLite so each track is fetched at most once. Negative
/// results are cached too, so offline/absent tracks don't re-query forever.
class LyricsService {
  final AppDatabase db;
  LyricsService(this.db);

  /// Dedupes concurrent requests only — entries evict on completion, so
  /// resolved lyric objects never accumulate (SQLite makes repeats cheap).
  final Map<String, Future<Lyrics?>> _inFlight = {};

  Future<Lyrics?> forTrack(Track t) => _inFlight.putIfAbsent(
      t.key, () => _load(t)..whenComplete(() => _inFlight.remove(t.key)));

  Future<Lyrics?> _load(Track t) async {
    try {
      final cached = await db.db
          .query('lyrics', where: 'track_key = ?', whereArgs: [t.key]);
      if (cached.isNotEmpty) {
        final synced = cached.first['synced'] as String? ?? '';
        final plain = cached.first['plain'] as String? ?? '';
        if (synced.isEmpty && plain.isEmpty) return null; // cached miss
        return Lyrics(synced: parseLrc(synced), plain: plain);
      }
    } catch (_) {}

    String synced = '';
    String plain = '';
    try {
      final result = await _fetchLrclib(t);
      synced = result.$1;
      plain = result.$2;
    } catch (_) {
      // Network failure — don't cache, so a later attempt can retry.
      _inFlight.remove(t.key);
      return null;
    }
    try {
      await db.db.insert(
          'lyrics',
          {
            'track_key': t.key,
            'synced': synced,
            'plain': plain,
            'fetched_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {}
    if (synced.isEmpty && plain.isEmpty) return null;
    return Lyrics(synced: parseLrc(synced), plain: plain);
  }

  /// Exact match first (duration-aware), then best-effort search.
  Future<(String, String)> _fetchLrclib(Track t) async {
    const headers = {'User-Agent': 'PapaAudio/1.0 (personal music player)'};
    final get = Uri.https('lrclib.net', '/api/get', {
      'artist_name': t.artist,
      'track_name': t.title,
      if (t.album != null) 'album_name': t.album!,
      if (t.duration > 0) 'duration': '${t.duration.round()}',
    });
    var r = await http.get(get, headers: headers)
        .timeout(const Duration(seconds: 12));
    if (r.statusCode == 200) {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      return ((j['syncedLyrics'] ?? '') as String,
          (j['plainLyrics'] ?? '') as String);
    }
    // No exact hit — search and take the closest-duration result.
    final search = Uri.https(
        'lrclib.net', '/api/search', {'q': '${t.artist} ${t.title}'});
    r = await http.get(search, headers: headers)
        .timeout(const Duration(seconds: 12));
    if (r.statusCode == 200) {
      final list = jsonDecode(r.body) as List;
      Map<String, dynamic>? best;
      double bestDiff = double.infinity;
      for (final e in list.whereType<Map<String, dynamic>>()) {
        final d = (e['duration'] as num?)?.toDouble() ?? 0;
        final diff =
            t.duration > 0 ? (d - t.duration).abs() : 0.0;
        final hasAny = ((e['syncedLyrics'] ?? '') as String).isNotEmpty ||
            ((e['plainLyrics'] ?? '') as String).isNotEmpty;
        if (hasAny && diff < bestDiff) {
          bestDiff = diff;
          best = e;
        }
      }
      if (best != null && (t.duration <= 0 || bestDiff <= 8)) {
        return ((best['syncedLyrics'] ?? '') as String,
            (best['plainLyrics'] ?? '') as String);
      }
    }
    return ('', '');
  }
}
