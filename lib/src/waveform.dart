import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import 'db.dart';
import 'models.dart';

/// Waveform bars for the seekbar. Extraction (a full native PCM decode) runs
/// once per track on a dedicated platform worker; results live in SQLite and a
/// small in-memory LRU. Only tracks with an on-device source qualify —
/// remote/bridge streams fall back to the plain slider.
class WaveformService {
  static const bucketCount = 96;
  static const _ch = MethodChannel('papa.audio/media_store');
  static const _memCap = 24;

  final AppDatabase db;
  WaveformService(this.db);

  final Map<String, Future<List<double>?>> _cache = {}; // LRU by re-insert

  static bool eligible(Track t) {
    final s = t.sourceUri;
    return s != null && (s.startsWith('content://') || s.startsWith('file://'));
  }

  Future<List<double>?> forTrack(Track t) {
    if (!eligible(t)) return Future.value(null);
    final hit = _cache.remove(t.key);
    if (hit != null) {
      _cache[t.key] = hit;
      return hit;
    }
    final future = _load(t);
    _cache[t.key] = future;
    while (_cache.length > _memCap) {
      _cache.remove(_cache.keys.first);
    }
    return future;
  }

  Future<List<double>?> _load(Track t) async {
    try {
      final rows = await db.db
          .query('waveforms', where: 'track_key = ?', whereArgs: [t.key]);
      if (rows.isNotEmpty) {
        final bars = (jsonDecode(rows.first['bars'] as String) as List)
            .map((e) => (e as num).toDouble())
            .toList();
        return bars.isEmpty ? null : bars; // empty = cached "can't extract"
      }
    } catch (_) {}

    List<double>? bars;
    try {
      final raw = await _ch.invokeListMethod<double>('getWaveform', {
        'uri': t.sourceUri,
        'buckets': bucketCount,
      });
      bars = raw?.map((e) => (e * 1000).round() / 1000).toList();
    } catch (_) {
      bars = null;
    }
    try {
      await db.db.insert(
          'waveforms',
          {
            'track_key': t.key,
            'bars': jsonEncode(bars ?? []),
            'generated_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {}
    return bars;
  }
}
