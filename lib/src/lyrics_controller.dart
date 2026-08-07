import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Lyrics controller — LRC synced + plain text from multiple sources.
///
/// Sources (tried in order):
///   1. Embedded lyrics (via MediaStore tag)
///   2. Local .lrc file next to the audio file
///   3. SQLite cache
///   4. lrclib.net API
///   5. Google search fallback
class LyricsController {
  LyricsController._();
  static final LyricsController inst = LyricsController._();

  final Map<String, _CachedLyrics> _cache = {};
  bool _prioritizeEmbedded = true;
  bool _stretchEnabled = true;
  Database? _db;

  /// Attach database instance (called during app startup).
  void attachDatabase(Database db) => _db = db;

  // ---- public API ----

  Future<void> init() async {
    final prefs = SharedPreferences.getInstance();
    final p = await prefs;
    _prioritizeEmbedded = p.getBool('lyrics_prioritizeEmbedded') ?? true;
    _stretchEnabled = p.getBool('lyrics_stretchEnabled') ?? true;
  }

  bool get prioritizeEmbedded => _prioritizeEmbedded;
  set prioritizeEmbedded(bool v) {
    _prioritizeEmbedded = v;
    SharedPreferences.getInstance().then((p) => p.setBool('lyrics_prioritizeEmbedded', v));
  }

  bool get stretchEnabled => _stretchEnabled;
  set stretchEnabled(bool v) {
    _stretchEnabled = v;
    SharedPreferences.getInstance().then((p) => p.setBool('lyrics_stretchEnabled', v));
  }

  /// Fetch lyrics for [track]. Returns parsed LRC lines (synced) or plain text.
  Future<LyricsResult> fetch(Track track) async {
    final key = '${track.artist}|${track.title}';
    // cache hit
    if (_cache.containsKey(key)) {
      final c = _cache[key]!;
      if (c.expiresAt.isAfter(DateTime.now())) return c.result;
    }
    // 1) embedded
    if (_prioritizeEmbedded) {
      try {
        final embedded = await _readEmbedded(track.path);
        if (embedded != null && embedded.isNotEmpty) {
          return _cacheAndReturn(key, LyricsResult.parse(embedded));
        }
      } catch (_) {}
    }
    // 2) local .lrc
    try {
      final lrcPath = '${track.path.substring(0, track.path.lastIndexOf('.'))}.lrc';
      final lrcFile = File(lrcPath);
      if (await lrcFile.exists()) {
        return _cacheAndReturn(key, LyricsResult.parse(await lrcFile.readAsString()));
      }
    } catch (_) {}
    // 3) DB cache
    try {
      final rows = await _db?.query('lyrics', where: 'track_key = ?', whereArgs: [key], limit: 1);
      if (rows.isNotEmpty) {
        return _cacheAndReturn(key, LyricsResult.fromJson(jsonDecode(rows.first['data'] as String)));
      }
    } catch (_) {}
    // 4) lrclib.net
    try {
      final res = await http.get(
        Uri.parse('https://lrclib.net/api/get?artist_name=${Uri.encodeComponent(track.artist)}&track_name=${Uri.encodeComponent(track.title)}'),
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final synced = body['syncedLyrics'] as String?;
        final plain = body['plainLyrics'] as String?;
        if (synced != null && synced.isNotEmpty) {
          await _saveToDb(key, synced);
          return _cacheAndReturn(key, LyricsResult.parseSynced(synced));
        }
        if (plain != null && plain.isNotEmpty) {
          await _saveToDb(key, plain);
          return _cacheAndReturn(key, LyricsResult.plain(plain));
        }
      }
    } catch (_) {}
    // 5) Google search fallback — simple page scrape
    try {
      final query = '${track.artist} ${track.title} lyrics';
      final res = await http.get(
        Uri.parse('https://www.google.com/search?q=${Uri.encodeComponent(query)}'),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = res.body;
        // Very basic extraction — real implementation would use an HTML parser
        final lyricMatch = RegExp(r'<div[^>]*data-lyricid[^>]*>(.*?)</div>', dotAll: true).firstMatch(body);
        if (lyricMatch != null) {
          final raw = _stripHtml(lyricMatch.group(1) ?? '');
          if (raw.length > 20) {
            await _saveToDb(key, raw);
            return _cacheAndReturn(key, LyricsResult.plain(raw));
          }
        }
      }
    } catch (_) {}

    return LyricsResult.empty;
  }

  /// Fetch lyrics via platform channel (embedded tags on Android).
  Future<String?> _readEmbedded(String path) async {
    try {
      final result = await MethodChannel('com.example.papa_audio/media')
          .invokeMethod<String>('readEmbeddedLyrics', {'path': path});
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveToDb(String key, String text) async {
    try {
      await _db?.insert('lyrics', {
        'track_key': key,
        'data': jsonEncode({'synced': text.contains('[') && text.contains(']'), 'text': text}),
        'cached_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {}
  }

  LyricsResult _cacheAndReturn(String key, LyricsResult result) {
    _cache[key] = _CachedLyrics(result: result, expiresAt: DateTime.now().add(const Duration(hours: 24)));
    return result;
  }

  String _stripHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&amp;', '&').replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&#39;', "'");
  }

  void clearCache() => _cache.clear();
}

class _CachedLyrics {
  final LyricsResult result;
  final DateTime expiresAt;
  _CachedLyrics({required this.result, required this.expiresAt});
}

/// Result from lyrics lookup.
class LyricsResult {
  final List<LrcLine> synced;
  final String plain;
  bool get hasSynced => synced.isNotEmpty;
  bool get hasPlain => plain.isNotEmpty;
  bool get isEmpty => !hasSynced && !hasPlain;

  LyricsResult._({required this.synced, required this.plain});

  factory LyricsResult.empty = LyricsResult._empty;
  LyricsResult._empty() : synced = const [], plain = '';

  factory LyricsResult.plain(String text) => LyricsResult._(synced: const [], plain: text);

  factory LyricsResult.parse(String raw) {
    if (raw.contains('[') && raw.contains(']') && RegExp(r'\[\d+:\d+').hasMatch(raw)) {
      return LyricsResult.parseSynced(raw);
    }
    return LyricsResult.plain(raw);
  }

  factory LyricsResult.parseSynced(String raw) {
    final lines = <LrcLine>[];
    for (final line in raw.split('\n')) {
      final match = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\](.*)').firstMatch(line.trim());
      if (match != null) {
        final min = int.parse(match.group(1)!);
        final sec = double.parse(match.group(2)!);
        final ms = ((min * 60 + sec) * 1000).round();
        lines.add(LrcLine(ms: ms, text: match.group(3)?.trim() ?? ''));
      }
    }
    lines.sort((a, b) => a.ms.compareTo(b.ms));
    return LyricsResult._(synced: lines, plain: raw);
  }

  Map<String, dynamic> toJson() => {
    'synced': synced.map((e) => {'ms': e.ms, 'text': e.text}).toList(),
    'plain': plain,
  };

  factory LyricsResult.fromJson(Map<String, dynamic> json) {
    final synced = (json['synced'] as List?)
        ?.map((e) => LrcLine(ms: (e['ms'] as num).toInt(), text: e['text'] as String))
        .toList() ?? [];
    return LyricsResult._(synced: synced, plain: json['plain'] as String? ?? '');
  }
}

class LrcLine {
  final int ms;
  final String text;
  const LrcLine({required this.ms, required this.text});
}
