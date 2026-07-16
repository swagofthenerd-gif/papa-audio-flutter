import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// The app's SQLite store. Replaces the whole-file JSON rewrites the first
/// versions used: a listen is now one INSERT, a favorite toggle one row, a
/// playlist edit one transaction — nothing rewrites megabytes on a timer, so
/// persistence stays O(change) no matter how large the library or history
/// grows. sqflite runs its work on a platform thread, off the UI isolate.
class AppDatabase {
  final Database db;
  AppDatabase._(this.db);

  static Future<AppDatabase> open() async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      '$dir${Platform.pathSeparator}papa_audio.db',
      version: 3,
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) await _createLyricsTable(db);
        if (oldVersion < 3) await _createV3Tables(db);
      },
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE history('
            'id INTEGER PRIMARY KEY AUTOINCREMENT,'
            'at INTEGER NOT NULL,'
            'track_key TEXT NOT NULL,'
            'track_json TEXT NOT NULL)');
        await db.execute('CREATE INDEX idx_history_at ON history(at)');
        await db.execute('CREATE INDEX idx_history_key ON history(track_key)');
        await db.execute('CREATE TABLE favorites('
            'track_key TEXT PRIMARY KEY,'
            'added_at INTEGER NOT NULL,'
            'track_json TEXT NOT NULL)');
        await db.execute('CREATE TABLE playlists('
            'id TEXT PRIMARY KEY,'
            'name TEXT NOT NULL,'
            'created_at INTEGER NOT NULL,'
            'modified_at INTEGER NOT NULL)');
        await db.execute('CREATE TABLE playlist_tracks('
            'playlist_id TEXT NOT NULL,'
            'pos INTEGER NOT NULL,'
            'track_json TEXT NOT NULL,'
            'PRIMARY KEY(playlist_id, pos))');
        await db.execute('CREATE TABLE queue_tracks('
            'pos INTEGER PRIMARY KEY,'
            'track_json TEXT NOT NULL)');
        await db.execute('CREATE TABLE saved_queues('
            'at INTEGER PRIMARY KEY,'
            'sig TEXT NOT NULL,'
            'tracks_json TEXT NOT NULL)');
        await db.execute('CREATE TABLE kv('
            'k TEXT PRIMARY KEY,'
            'v TEXT NOT NULL)');
        await _createLyricsTable(db);
        await _createV3Tables(db);
      },
    );
    final wrapper = AppDatabase._(db);
    await wrapper._importLegacyJson();
    return wrapper;
  }

  static Future<void> _createLyricsTable(Database db) => db.execute(
      'CREATE TABLE IF NOT EXISTS lyrics('
      'track_key TEXT PRIMARY KEY,'
      'synced TEXT NOT NULL,'
      'plain TEXT NOT NULL,'
      'fetched_at INTEGER NOT NULL)');

  static Future<void> _createV3Tables(Database db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS waveforms('
        'track_key TEXT PRIMARY KEY,'
        'bars TEXT NOT NULL,'
        'generated_at INTEGER NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS collection_resume('
        'collection_id TEXT PRIMARY KEY,'
        'track_index INTEGER NOT NULL,'
        'position_ms INTEGER NOT NULL,'
        'track_title TEXT,'
        'updated_at INTEGER NOT NULL)');
  }

  // ── kv helpers ──────────────────────────────────────────────────────────────

  Future<String?> getKv(String key) async {
    final rows = await db.query('kv', where: 'k = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['v'] as String;
  }

  Future<void> setKv(String key, String value) => db.insert(
      'kv', {'k': key, 'v': value},
      conflictAlgorithm: ConflictAlgorithm.replace);

  // ── One-time import of the old JSON stores ─────────────────────────────────

  Future<void> _importLegacyJson() async {
    if (await getKv('migrated_json') == '1') return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      String p(String name) => '${docs.path}${Platform.pathSeparator}$name';

      Future<dynamic> readJson(String name) async {
        final f = File(p(name));
        if (!await f.exists()) return null;
        try {
          return await compute(_decode, await f.readAsString());
        } catch (_) {
          return null;
        }
      }

      final history = await readJson('history.json');
      if (history is List && history.isNotEmpty) {
        final batch = db.batch();
        // File was newest-first; insert oldest-first so ids grow with time.
        for (final e in history.reversed) {
          if (e is! Map) continue;
          final track = e['track'];
          if (track is! Map) continue;
          batch.insert('history', {
            'at': (e['at'] as num?)?.toInt() ?? 0,
            // Mirror Track.key (id ?? filePath) so migrated listens merge with
            // new ones instead of colliding on an empty key.
            'track_key': (track['id'] ?? track['filePath'] ?? '').toString(),
            'track_json': jsonEncode(track),
          });
        }
        await batch.commit(noResult: true);
      }

      final playlists = await readJson('playlists.json');
      if (playlists is Map) {
        final batch = db.batch();
        for (final t in (playlists['favorites'] as List? ?? [])) {
          if (t is! Map) continue;
          batch.insert(
              'favorites',
              {
                'track_key': (t['id'] ?? t['filePath'] ?? '').toString(),
                'added_at': 0,
                'track_json': jsonEncode(t),
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (final pl in (playlists['playlists'] as List? ?? [])) {
          if (pl is! Map) continue;
          final id = (pl['id'] ?? '').toString();
          batch.insert(
              'playlists',
              {
                'id': id,
                'name': (pl['name'] ?? 'Playlist').toString(),
                'created_at': (pl['createdAt'] as num?)?.toInt() ?? 0,
                'modified_at': (pl['modifiedAt'] as num?)?.toInt() ?? 0,
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
          final tracks = pl['tracks'] as List? ?? [];
          for (var i = 0; i < tracks.length; i++) {
            batch.insert(
                'playlist_tracks',
                {
                  'playlist_id': id,
                  'pos': i,
                  'track_json': jsonEncode(tracks[i]),
                },
                conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
        await batch.commit(noResult: true);
      }

      final queue = await readJson('queue.json');
      if (queue is Map && queue['tracks'] is List) {
        final batch = db.batch();
        final tracks = queue['tracks'] as List;
        for (var i = 0; i < tracks.length; i++) {
          batch.insert('queue_tracks',
              {'pos': i, 'track_json': jsonEncode(tracks[i])},
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
        final pos = await readJson('queue_pos.json');
        if (pos is Map) {
          await setKv('queue_index', '${(pos['index'] as num?)?.toInt() ?? 0}');
          await setKv('queue_position_ms',
              '${(pos['positionMs'] as num?)?.toInt() ?? 0}');
        }
      }

      final queues = await readJson('queues.json');
      if (queues is List) {
        final batch = db.batch();
        for (final q in queues) {
          if (q is! Map) continue;
          final tracks = q['tracks'] as List? ?? [];
          batch.insert(
              'saved_queues',
              {
                'at': (q['at'] as num?)?.toInt() ?? 0,
                // Match QueuesStore.sigOf so the runtime dedup DELETE finds this
                // migrated row instead of leaving a duplicate.
                'sig': _legacyQueueSig(tracks),
                'tracks_json': jsonEncode(tracks),
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      }

      // Keep the originals as .bak — data safety over tidiness.
      for (final name in [
        'history.json', 'playlists.json', 'queue.json',
        'queue_pos.json', 'queues.json'
      ]) {
        final f = File(p(name));
        if (await f.exists()) {
          try {
            await f.rename(p('$name.bak'));
          } catch (_) {}
        }
      }
    } catch (_) {
      // Migration is best-effort; a fresh DB is still a working app.
    }
    await setKv('migrated_json', '1');
  }
}

dynamic _decode(String raw) => jsonDecode(raw);

/// Mirrors QueuesStore.sigOf (kept here to avoid a cross-import) so migrated
/// saved-queue rows carry the same signature the runtime dedup expects.
String _legacyQueueSig(List tracks) {
  var h = 0;
  for (final t in tracks) {
    final id = (t is Map ? (t['id'] ?? t['filePath'] ?? '') : '').toString();
    h = 0x1fffffff & (h * 31 + id.hashCode);
  }
  return 'h$h:${tracks.length}';
}
