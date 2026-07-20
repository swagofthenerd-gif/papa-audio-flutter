import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'db.dart';
import 'models.dart';

/// User playlists + favorites, backed by SQLite. Every mutation is a targeted
/// statement or a per-playlist transaction — no whole-store rewrites.
class PlaylistsService extends ChangeNotifier {
  List<Playlist> playlists = [];
  final Set<String> _favoriteKeys = {};
  List<Track> _favoriteTracks = [];

  AppDatabase? _db;

  List<Track> get favorites => _favoriteTracks;
  bool isFavorite(Track t) => _favoriteKeys.contains(t.key);

  /// Bumped on every change so views (and recommendations) can memoize
  /// playlist/favorite-derived data instead of recomputing on every rebuild.
  int revision = 0;

  @override
  void notifyListeners() {
    revision++;
    super.notifyListeners();
  }

  Future<void> init(AppDatabase db) async {
    _db = db;
    try {
      final favRows =
          await db.db.query('favorites', orderBy: 'added_at ASC');
      _favoriteTracks = [
        for (final r in favRows)
          Track.fromJson(
              jsonDecode(r['track_json'] as String) as Map<String, dynamic>)
      ];
      _favoriteKeys
        ..clear()
        ..addAll(_favoriteTracks.map((t) => t.key));

      final plRows = await db.db.query('playlists', orderBy: 'created_at ASC');
      final trackRows = await db.db.query('playlist_tracks', orderBy: 'pos ASC');
      final byPlaylist = <String, List<Track>>{};
      for (final r in trackRows) {
        byPlaylist
            .putIfAbsent(r['playlist_id'] as String, () => [])
            .add(Track.fromJson(
                jsonDecode(r['track_json'] as String) as Map<String, dynamic>));
      }
      playlists = [
        for (final r in plRows)
          Playlist(
            id: r['id'] as String,
            name: r['name'] as String,
            tracks: byPlaylist[r['id'] as String] ?? [],
            createdAt: r['created_at'] as int,
            modifiedAt: r['modified_at'] as int,
          )
      ];
    } catch (_) {
      playlists = [];
      _favoriteTracks = [];
    }
    notifyListeners();
  }

  Future<void> toggleFavorite(Track t) async {
    if (!_favoriteKeys.add(t.key)) {
      _favoriteKeys.remove(t.key);
      _favoriteTracks.removeWhere((x) => x.key == t.key);
      try {
        await _db?.db
            .delete('favorites', where: 'track_key = ?', whereArgs: [t.key]);
      } catch (_) {}
    } else {
      _favoriteTracks.add(t);
      try {
        await _db?.db.insert(
            'favorites',
            {
              'track_key': t.key,
              'added_at': DateTime.now().millisecondsSinceEpoch,
              'track_json': jsonEncode(t.toJson()),
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      } catch (_) {}
    }
    notifyListeners();
  }

  int _plSeq = 0;

  Future<Playlist> create(String name) async {
    // A bare millisecond id collides when two playlists are created in the same
    // millisecond (e.g. a scripted import loop); a monotonic suffix disambiguates.
    final p = Playlist(
      id: 'pl_${DateTime.now().millisecondsSinceEpoch}_${_plSeq++}',
      name: name.trim().isEmpty ? 'Playlist ${playlists.length + 1}' : name.trim(),
      tracks: [],
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    playlists.add(p);
    notifyListeners();
    try {
      await _db?.db.insert('playlists', {
        'id': p.id,
        'name': p.name,
        'created_at': p.createdAt,
        'modified_at': p.modifiedAt,
      });
    } catch (_) {}
    return p;
  }

  Future<void> rename(Playlist p, String name) async {
    if (name.trim().isEmpty) return;
    p.name = name.trim();
    p.modifiedAt = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    try {
      await _db?.db.update(
          'playlists', {'name': p.name, 'modified_at': p.modifiedAt},
          where: 'id = ?', whereArgs: [p.id]);
    } catch (_) {}
  }

  Future<void> delete(Playlist p) async {
    playlists.removeWhere((x) => x.id == p.id);
    notifyListeners();
    try {
      await _db?.db.transaction((txn) async {
        await txn.delete('playlists', where: 'id = ?', whereArgs: [p.id]);
        await txn.delete('playlist_tracks',
            where: 'playlist_id = ?', whereArgs: [p.id]);
      });
    } catch (_) {}
  }

  /// Appends; duplicates are allowed (playlists are ordered lists, not sets).
  Future<void> addTracks(Playlist p, List<Track> tracks) async {
    final start = p.tracks.length;
    p.tracks.addAll(tracks);
    p.modifiedAt = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    try {
      final batch = _db?.db.batch();
      if (batch != null) {
        for (var i = 0; i < tracks.length; i++) {
          batch.insert(
              'playlist_tracks',
              {
                'playlist_id': p.id,
                'pos': start + i,
                'track_json': jsonEncode(tracks[i].toJson()),
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        batch.update('playlists', {'modified_at': p.modifiedAt},
            where: 'id = ?', whereArgs: [p.id]);
        await batch.commit(noResult: true);
      }
    } catch (_) {}
  }

  Future<void> removeAt(Playlist p, int index) async {
    if (index < 0 || index >= p.tracks.length) return;
    p.tracks.removeAt(index);
    p.modifiedAt = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    await _rewriteTracks(p);
  }

  /// Re-insert a track at [index] (used to undo a [removeAt]).
  Future<void> insertAt(Playlist p, int index, Track t) async {
    p.tracks.insert(index.clamp(0, p.tracks.length), t);
    p.modifiedAt = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    await _rewriteTracks(p);
  }

  /// Keeps the first occurrence of each track; returns how many rows left.
  Future<int> removeDuplicates(Playlist p) async {
    final seen = <String>{};
    final before = p.tracks.length;
    p.tracks.retainWhere((t) => seen.add(t.key));
    final removed = before - p.tracks.length;
    if (removed == 0) return 0;
    p.modifiedAt = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    await _rewriteTracks(p);
    return removed;
  }

  Future<void> reorder(Playlist p, int from, int to) async {
    if (from < 0 || from >= p.tracks.length) return;
    final t = p.tracks.removeAt(from);
    p.tracks.insert(to.clamp(0, p.tracks.length), t);
    p.modifiedAt = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    await _rewriteTracks(p);
  }

  /// Positions changed — rewrite THIS playlist's rows in one transaction.
  Future<void> _rewriteTracks(Playlist p) async {
    try {
      await _db?.db.transaction((txn) async {
        await txn.delete('playlist_tracks',
            where: 'playlist_id = ?', whereArgs: [p.id]);
        final batch = txn.batch();
        for (var i = 0; i < p.tracks.length; i++) {
          batch.insert('playlist_tracks', {
            'playlist_id': p.id,
            'pos': i,
            'track_json': jsonEncode(p.tracks[i].toJson()),
          });
        }
        batch.update('playlists', {'modified_at': p.modifiedAt},
            where: 'id = ?', whereArgs: [p.id]);
        await batch.commit(noResult: true);
      });
    } catch (_) {}
  }
}

class Playlist {
  final String id;
  String name;
  final List<Track> tracks;
  final int createdAt;
  int modifiedAt;

  Playlist({
    required this.id,
    required this.name,
    required this.tracks,
    required this.createdAt,
    int? modifiedAt,
  }) : modifiedAt = modifiedAt ?? createdAt;

  double get totalDuration => tracks.fold(0, (s, t) => s + t.duration);
}
