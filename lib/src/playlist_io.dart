import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'models.dart';
import 'playlists.dart';

/// Import/export playlists in M3U, PLS, and JSON formats.
class PlaylistImportExportService {
  final PlaylistService _playlists;

  PlaylistImportExportService(this._playlists);

  // ── Export ─────────────────────────────────────────────────────

  /// Export a playlist to M3U format.
  String exportToM3U(String playlistName) {
    final tracks = _playlists.getTracks(playlistName);
    final buf = StringBuffer('#EXTM3U\n');
    buf.writeln('#PLAYLIST:$playlistName');
    for (final track in tracks) {
      buf.writeln('#EXTINF:${track.duration},${track.artist} - ${track.title}');
      buf.writeln(track.path);
    }
    return buf.toString();
  }

  /// Export a playlist to PLS format.
  String exportToPLS(String playlistName) {
    final tracks = _playlists.getTracks(playlistName);
    final buf = StringBuffer('[playlist]\n');
    buf.writeln('NumberOfEntries=${tracks.length}');
    for (var i = 0; i < tracks.length; i++) {
      final n = i + 1;
      buf.writeln('File$n=${tracks[i].path}');
      buf.writeln('Title$n=${tracks[i].artist} - ${tracks[i].title}');
      buf.writeln('Length$n=${tracks[i].duration}');
    }
    return buf.toString();
  }

  /// Export a playlist to JSON format (full metadata).
  String exportToJSON(String playlistName) {
    final tracks = _playlists.getTracks(playlistName);
    return jsonEncode({
      'name': playlistName,
      'exportedAt': DateTime.now().toIso8601String(),
      'tracks': tracks.map((t) => t.toJson()).toList(),
    });
  }

  /// Share a playlist file.
  Future<void> sharePlaylist(
      String playlistName, String format) async {
    String content;
    String ext;
    switch (format) {
      case 'm3u':
        content = exportToM3U(playlistName);
        ext = '.m3u';
        break;
      case 'pls':
        content = exportToPLS(playlistName);
        ext = '.pls';
        break;
      case 'json':
        content = exportToJSON(playlistName);
        ext = '.json';
        break;
      default:
        return;
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$playlistName$ext');
    await file.writeAsString(content);
    await Share.shareXFiles([XFile(file.path)], text: playlistName);
  }

  /// Save playlist to a user-chosen location.
  Future<String> saveToFile(String playlistName, String format) async {
    String content;
    String ext;
    switch (format) {
      case 'm3u':
        content = exportToM3U(playlistName);
        ext = '.m3u';
        break;
      case 'pls':
        content = exportToPLS(playlistName);
        ext = '.pls';
        break;
      case 'json':
        content = exportToJSON(playlistName);
        ext = '.json';
        break;
      default:
        throw ArgumentError('Unknown format: $format');
    }

    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/exports');
    if (!exportDir.existsSync()) {
      exportDir.createSync(recursive: true);
    }
    final file =
        File('${exportDir.path}/$playlistName$ext');
    await file.writeAsString(content);
    return file.path;
  }

  // ── Import ─────────────────────────────────────────────────────

  /// Import a playlist from an M3U file.
  Future<int> importFromM3U(String filePath, String playlistName) async {
    final file = File(filePath);
    if (!file.existsSync()) return 0;
    final lines = await file.readAsLines();
    final tracks = <Track>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('#') || line.isEmpty) continue;
      // Attempt to extract metadata from preceding #EXTINF line
      String? title;
      String? artist;
      int duration = 0;
      if (i > 0 && lines[i - 1].startsWith('#EXTINF:')) {
        final extinf = lines[i - 1];
        final durMatch = RegExp(r'#EXTINF:(\d+)').firstMatch(extinf);
        if (durMatch != null) {
          duration = int.tryParse(durMatch.group(1)!) ?? 0;
        }
        final titlePart =
            extinf.split(',').length > 1 ? extinf.split(',').last : '';
        final parts = titlePart.split(' - ');
        if (parts.length >= 2) {
          artist = parts[0].trim();
          title = parts.sublist(1).join(' - ').trim();
        } else {
          title = titlePart.trim();
        }
      }
      tracks.add(Track(
        path: line,
        title: title ?? line.split('/').last,
        artist: artist ?? '',
        duration: duration,
      ));
    }

    if (tracks.isEmpty) return 0;
    _playlists.createPlaylist(playlistName, tracks);
    return tracks.length;
  }

  /// Import a playlist from a JSON file.
  Future<int> importFromJSON(String filePath, {String? playlistName}) async {
    final file = File(filePath);
    if (!file.existsSync()) return 0;
    try {
      final data = jsonDecode(await file.readAsString());
      final name = playlistName ?? data['name'] ?? 'Imported Playlist';
      final trackList = (data['tracks'] as List?)
              ?.map((j) => Track.fromJson(j))
              .toList() ??
          [];
      if (trackList.isEmpty) return 0;
      _playlists.createPlaylist(name, trackList);
      return trackList.length;
    } catch (_) {
      return 0;
    }
  }

  /// Import a playlist from a PLS file.
  Future<int> importFromPLS(String filePath, String playlistName) async {
    final file = File(filePath);
    if (!file.existsSync()) return 0;
    final lines = await file.readAsLines();
    final tracks = <Track>[];
    final fileMap = <int, String>{};
    final titleMap = <int, String>{};
    final lengthMap = <int, int>{};

    for (final line in lines) {
      final eq = line.indexOf('=');
      if (eq < 0) continue;
      final key = line.substring(0, eq).trim();
      final value = line.substring(eq + 1).trim();

      final fileMatch = RegExp(r'^File(\d+)$').firstMatch(key);
      if (fileMatch != null) {
        fileMap[int.parse(fileMatch.group(1)!)] = value;
      }
      final titleMatch = RegExp(r'^Title(\d+)$').firstMatch(key);
      if (titleMatch != null) {
        titleMap[int.parse(titleMatch.group(1)!)] = value;
      }
      final lengthMatch = RegExp(r'^Length(\d+)$').firstMatch(key);
      if (lengthMatch != null) {
        lengthMap[int.parse(lengthMatch.group(1)!)] =
            int.tryParse(value) ?? 0;
      }
    }

    for (final entry in fileMap.entries) {
      final path = entry.value;
      final titleStr = titleMap[entry.key] ?? '';
      final parts = titleStr.split(' - ');
      tracks.add(Track(
        path: path,
        title: parts.length >= 2
            ? parts.sublist(1).join(' - ').trim()
            : titleStr,
        artist: parts.length >= 2 ? parts[0].trim() : '',
        duration: lengthMap[entry.key] ?? 0,
      ));
    }

    if (tracks.isEmpty) return 0;
    _playlists.createPlaylist(playlistName, tracks);
    return tracks.length;
  }
}
