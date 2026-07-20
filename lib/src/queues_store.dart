import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'db.dart';
import 'models.dart';
import 'player_service.dart' show encodeTracksJson;

/// Auto-archive of played queues, backed by SQLite: every new queue is
/// snapshotted with its timestamp so any listening session can be replayed
/// from the Queues tab. Capped — old snapshots roll off.
class QueuesStore extends ChangeNotifier {
  static const _cap = 30;

  List<SavedQueue> saved = []; // newest first
  AppDatabase? _db;

  Future<void> init(AppDatabase db) async {
    _db = db;
    try {
      final rows = await db.db.query('saved_queues', orderBy: 'at DESC');
      saved = [
        for (final r in rows)
          SavedQueue(
            at: r['at'] as int,
            tracks: [
              for (final t in jsonDecode(r['tracks_json'] as String) as List)
                Track.fromJson(t as Map<String, dynamic>)
            ],
          )
      ];
    } catch (_) {
      saved = [];
    }
    notifyListeners();
  }

  /// Cheap order-sensitive signature — no giant string concatenations.
  static String sigOf(List<Track> tracks) {
    var h = 0;
    for (final t in tracks) {
      h = 0x1fffffff & (h * 31 + t.key.hashCode);
    }
    return 'h$h:${tracks.length}';
  }

  /// Called by the player whenever a NEW queue starts. Replaying the same set
  /// of tracks refreshes the existing snapshot instead of duplicating it.
  void record(List<Track> tracks) {
    if (tracks.isEmpty) return;
    final sig = sigOf(tracks);
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = saved.indexWhere((q) => q.sig == sig);
    SavedQueue snapshot;
    if (existing >= 0) {
      snapshot = SavedQueue(at: now, tracks: saved.removeAt(existing).tracks);
    } else {
      snapshot = SavedQueue(at: now, tracks: List.of(tracks));
    }
    saved.insert(0, snapshot);
    if (saved.length > _cap) saved.removeRange(_cap, saved.length);
    notifyListeners();
    _persist(snapshot, sig);
  }

  Future<void> _persist(SavedQueue q, String sig) async {
    try {
      // Encode off the UI isolate; join the pre-encoded rows cheaply.
      final encoded = await compute(encodeTracksJson, q.tracks);
      await _db?.db.transaction((txn) async {
        await txn.delete('saved_queues', where: 'sig = ?', whereArgs: [sig]);
        await txn.insert(
            'saved_queues',
            {
              'at': q.at,
              'sig': sig,
              'tracks_json': '[${encoded.join(',')}]',
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.rawDelete(
            'DELETE FROM saved_queues WHERE at NOT IN '
            '(SELECT at FROM saved_queues ORDER BY at DESC LIMIT ?)',
            [_cap]);
      });
    } catch (_) {}
  }

  Future<void> delete(SavedQueue q) async {
    saved.remove(q);
    notifyListeners();
    try {
      await _db?.db
          .delete('saved_queues', where: 'at = ?', whereArgs: [q.at]);
    } catch (_) {}
  }

  /// Undo a [delete]: re-insert the snapshot in newest-first order and persist.
  Future<void> restore(SavedQueue q) async {
    if (saved.any((e) => e.at == q.at)) return;
    saved.add(q);
    saved.sort((a, b) => b.at.compareTo(a.at));
    notifyListeners();
    await _persist(q, q.sig);
  }
}

class SavedQueue {
  final int at; // epoch ms
  final List<Track> tracks;
  late final String sig = QueuesStore.sigOf(tracks);

  SavedQueue({required this.at, required this.tracks});
}
