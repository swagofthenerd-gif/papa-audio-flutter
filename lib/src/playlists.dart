import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// User playlists + favorites, persisted as JSON in the app documents dir.
/// Tracks are stored as full Track json so playlists survive even when a
/// source (bridge/local library) is unavailable at load time.
class PlaylistsService extends ChangeNotifier {
  List<Playlist> playlists = [];
  final Set<String> _favoriteKeys = {};
  List<Track> _favoriteTracks = [];

  File? _file;

  List<Track> get favorites => _favoriteTracks;
  bool isFavorite(Track t) => _favoriteKeys.contains(t.key);

  Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    _file = File('${docs.path}${Platform.pathSeparator}playlists.json');
    try {
      if (await _file!.exists()) {
        final j = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        playlists = ((j['playlists'] ?? []) as List)
            .map((p) => Playlist.fromJson(p as Map<String, dynamic>))
            .toList();
        _favoriteTracks = ((j['favorites'] ?? []) as List)
            .map((t) => Track.fromJson(t as Map<String, dynamic>))
            .toList();
        _favoriteKeys
          ..clear()
          ..addAll(_favoriteTracks.map((t) => t.key));
      }
    } catch (_) {
      // Corrupt store — start fresh rather than crash the app.
      playlists = [];
      _favoriteTracks = [];
    }
    notifyListeners();
  }

  Future<void> toggleFavorite(Track t) async {
    if (!_favoriteKeys.add(t.key)) {
      _favoriteKeys.remove(t.key);
      _favoriteTracks.removeWhere((x) => x.key == t.key);
    } else {
      _favoriteTracks.add(t);
    }
    notifyListeners();
    await _save();
  }

  Future<Playlist> create(String name) async {
    final p = Playlist(
      id: 'pl_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Playlist ${playlists.length + 1}' : name.trim(),
      tracks: [],
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    playlists.add(p);
    notifyListeners();
    await _save();
    return p;
  }

  Future<void> rename(Playlist p, String name) async {
    if (name.trim().isEmpty) return;
    p.name = name.trim();
    notifyListeners();
    await _save();
  }

  Future<void> delete(Playlist p) async {
    playlists.removeWhere((x) => x.id == p.id);
    notifyListeners();
    await _save();
  }

  /// Appends; duplicates are allowed (playlists are ordered lists, not sets).
  Future<void> addTracks(Playlist p, List<Track> tracks) async {
    p.tracks.addAll(tracks);
    p.modifiedAt = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    await _save();
  }

  Future<void> removeAt(Playlist p, int index) async {
    if (index < 0 || index >= p.tracks.length) return;
    p.tracks.removeAt(index);
    p.modifiedAt = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    await _save();
  }

  Future<void> reorder(Playlist p, int from, int to) async {
    if (from < 0 || from >= p.tracks.length) return;
    final t = p.tracks.removeAt(from);
    p.tracks.insert(to.clamp(0, p.tracks.length), t);
    p.modifiedAt = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    final f = _file;
    if (f == null) return;
    await f.writeAsString(jsonEncode({
      'playlists': playlists.map((p) => p.toJson()).toList(),
      'favorites': _favoriteTracks.map((t) => t.toJson()).toList(),
    }));
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

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? 'Playlist').toString(),
        tracks: ((j['tracks'] ?? []) as List)
            .map((t) => Track.fromJson(t as Map<String, dynamic>))
            .toList(),
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
        modifiedAt: (j['modifiedAt'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'createdAt': createdAt,
        'modifiedAt': modifiedAt,
      };
}
