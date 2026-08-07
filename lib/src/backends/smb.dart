import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

/// SMB / Windows network share client.
///
/// Uses plain file:// access through the Android file system.
/// For full SMB protocol support (auth, discovery), this would
/// require a native SMB library. This implementation works with
/// mounted shares.
class SmbService {
  String? _sharePath;
  bool _mounted = false;

  bool get isConnected => _mounted;

  Future<void> loadCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    _sharePath = prefs.getString('smb_path');
  }

  Future<bool> connect(String sharePath) async {
    // For Android: verify the path is accessible
    final dir = Directory(sharePath);
    final exists = await dir.exists();
    if (!exists) return false;

    _sharePath = sharePath;
    _mounted = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('smb_path', sharePath);
    return true;
  }

  Future<List<Album>> getAlbums() async {
    if (!_mounted || _sharePath == null) return [];
    return _scan(_sharePath!);
  }

  Future<List<Album>> _scan(String rootPath) async {
    final albums = <String, List<Track>>{};
    await _scanDir(Directory(rootPath), albums);
    return albums.entries.map((e) {
      return Album(
        name: e.key,
        artist: e.value.first.artist,
        trackCount: e.value.length,
      );
    }).toList();
  }

  Future<void> _scanDir(
      Directory dir, Map<String, List<Track>> albums) async {
    try {
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          await _scanDir(entity, albums);
        } else if (entity is File) {
          final ext = entity.path.split('.').lastOrNull?.toLowerCase();
          if (ext != null && _audioExts.contains(ext)) {
            final albumName =
                entity.parent.path.split('/').lastOrNull ?? 'Unknown';
            albums.putIfAbsent(albumName, () => []);
            albums[albumName]!.add(Track(
              path: entity.path,
              title: entity.path.split('/').last.replaceAll('.$ext', ''),
              artist: '',
              album: albumName,
              source: 'smb',
            ));
          }
        }
      }
    } catch (_) {}
  }

  String getStreamUrl(String path) => path;

  Future<void> disconnect() async {
    _mounted = false;
    _sharePath = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('smb_path');
  }

  static const _audioExts = {
    'mp3', 'flac', 'wav', 'aac', 'ogg', 'opus', 'm4a', 'wma',
    'alac', 'aiff', 'ape', 'dsf', 'dff', 'wv',
  };
}
