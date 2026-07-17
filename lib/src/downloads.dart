import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'bridge.dart';
import 'models.dart';
import 'yt/yt_service.dart';

/// Tracks downloaded from the bridge onto the phone, for offline playback.
/// Files live in the app's documents dir (no storage permission needed) with a
/// small JSON index alongside. Progress is exposed per track id while a
/// download is running.
class DownloadManager extends ChangeNotifier {
  Directory? _dir;
  int _lastProgressNotify = 0;
  final Map<String, double> progress = {}; // track id → 0..1 (in flight)
  final Map<String, String> failed = {}; // track id → error message
  List<Track> downloaded = []; // playable file:// tracks

  bool get busy => progress.isNotEmpty;

  Future<Directory> _downloadsDir() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}downloads');
    await dir.create(recursive: true);
    return _dir = dir;
  }

  File get _indexFile => File('${_dir!.path}${Platform.pathSeparator}index.json');

  Future<void> init() async {
    await _downloadsDir();
    try {
      if (await _indexFile.exists()) {
        final list = jsonDecode(await _indexFile.readAsString()) as List;
        downloaded = list
            .map((e) => _fromIndex(e as Map<String, dynamic>))
            .whereType<Track>()
            .toList();
      }
    } catch (_) {
      downloaded = []; // corrupt index — downloads can be re-done
    }
    notifyListeners();
  }

  bool isDownloaded(String trackId) => downloaded.any((t) => t.id == trackId);

  /// Download [t]'s original lossless file (raw=1) plus its artwork.
  Future<void> download(Track t, Bridge bridge) async {
    if (isDownloaded(t.id) || progress.containsKey(t.id)) return;
    final dir = await _downloadsDir();
    progress[t.id] = 0;
    failed.remove(t.id);
    notifyListeners();

    final base = _safeName(t.id);
    // Distinct ids that normalize to the same safe name would otherwise
    // overwrite each other's file; a short hash of the raw id keeps them apart.
    final unique = '${base}_${t.id.hashCode.toUnsigned(20).toRadixString(16)}';
    final audioFile = File('${dir.path}${Platform.pathSeparator}$unique${_ext(t.filePath)}');
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(bridge.streamUrl(t.filePath, raw: true)));
      final resp = await client.send(req).timeout(const Duration(minutes: 5));
      if (resp.statusCode != 200) throw 'HTTP ${resp.statusCode}';
      final total = resp.contentLength ?? 0;
      var received = 0;
      final sink = audioFile.openWrite();
      try {
        // A stalled LAN connection mid-body would otherwise hang forever,
        // wedging `busy`/progress and blocking album downloads. Cap idle gaps
        // between chunks.
        await for (final chunk
            in resp.stream.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            final p = received / total;
            progress[t.id] = p;
            // Time-throttled: at most ~4 rebuilds/second regardless of
            // network speed. (Perf audit finding.)
            final now = DateTime.now().millisecondsSinceEpoch;
            if (now - _lastProgressNotify >= 250) {
              _lastProgressNotify = now;
              notifyListeners();
            }
          }
        }
      } finally {
        await sink.close();
      }

      // Artwork is best-effort — playback matters, art doesn't.
      String? artFileName;
      final artUrl = bridge.artUrl(t.artPath, width: 600);
      if (artUrl != null) {
        try {
          final r = await http.get(Uri.parse(artUrl)).timeout(const Duration(seconds: 20));
          if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
            artFileName = '$unique.art.jpg';
            await File('${dir.path}${Platform.pathSeparator}$artFileName')
                .writeAsBytes(r.bodyBytes);
          }
        } catch (_) {}
      }

      downloaded.add(Track(
        id: t.id,
        title: t.title,
        artist: t.artist,
        album: t.album,
        filePath: t.filePath,
        trackNumber: t.trackNumber,
        discNumber: t.discNumber,
        duration: t.duration,
        sourceUri: audioFile.uri.toString(),
        artUri: artFileName != null
            ? File('${dir.path}${Platform.pathSeparator}$artFileName').uri.toString()
            : null,
      ));
      await _saveIndex();
    } catch (e) {
      failed[t.id] = e.toString();
      try {
        if (await audioFile.exists()) await audioFile.delete();
      } catch (_) {}
    } finally {
      client.close(); // release keep-alive sockets on every download
      progress.remove(t.id);
      notifyListeners();
    }
  }

  Future<void> downloadAlbum(Album album, Bridge bridge) async {
    // Sequential on purpose — parallel lossless downloads would fight for LAN
    // bandwidth and slow every track down.
    for (final t in album.tracks) {
      await download(t, bridge);
    }
  }

  /// On-device YouTube download: resolve the stream URL, save the audio to the
  /// same downloads dir (offline playback via [sourceUri]), fetch the thumbnail
  /// as art. Mirrors [download] but sources bytes from YT instead of the bridge.
  Future<void> downloadYt(Track t, YtStreamResolver resolver) async {
    if (isDownloaded(t.id) || progress.containsKey(t.id)) return;
    final videoId = t.id.startsWith('yt:') ? t.id.substring(3) : t.id;
    final dir = await _downloadsDir();
    progress[t.id] = 0;
    failed.remove(t.id);
    notifyListeners();

    final base = _safeName(t.id);
    final unique = '${base}_${t.id.hashCode.toUnsigned(20).toRadixString(16)}';
    final client = http.Client();
    File? audioFile;
    try {
      final stream = await resolver.resolve(videoId);
      final ext = stream.mime.contains('webm') ? '.webm' : '.m4a';
      audioFile = File('${dir.path}${Platform.pathSeparator}$unique$ext');
      final req = http.Request('GET', Uri.parse(stream.url));
      final resp = await client.send(req).timeout(const Duration(minutes: 5));
      if (resp.statusCode != 200) throw 'HTTP ${resp.statusCode}';
      final total = stream.contentLength ?? resp.contentLength ?? 0;
      var received = 0;
      final sink = audioFile.openWrite();
      try {
        await for (final chunk
            in resp.stream.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            progress[t.id] = received / total;
            final now = DateTime.now().millisecondsSinceEpoch;
            if (now - _lastProgressNotify >= 250) {
              _lastProgressNotify = now;
              notifyListeners();
            }
          }
        }
      } finally {
        await sink.close();
      }

      // Thumbnail (best-effort) — the YT art URL is a plain http image.
      String? artFileName;
      final artUrl = t.artUri;
      if (artUrl != null && artUrl.startsWith('http')) {
        try {
          final r = await http.get(Uri.parse(artUrl))
              .timeout(const Duration(seconds: 20));
          if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
            artFileName = '$unique.art.jpg';
            await File('${dir.path}${Platform.pathSeparator}$artFileName')
                .writeAsBytes(r.bodyBytes);
          }
        } catch (_) {}
      }

      downloaded.add(Track(
        id: t.id,
        title: t.title,
        artist: t.artist,
        album: t.album,
        filePath: t.filePath,
        duration: t.duration,
        sourceUri: audioFile.uri.toString(),
        artUri: artFileName != null
            ? File('${dir.path}${Platform.pathSeparator}$artFileName').uri.toString()
            : artUrl,
      ));
      await _saveIndex();
    } catch (e) {
      failed[t.id] = e.toString();
      try {
        if (audioFile != null && await audioFile.exists()) {
          await audioFile.delete();
        }
      } catch (_) {}
    } finally {
      client.close();
      progress.remove(t.id);
      notifyListeners();
    }
  }

  Future<void> remove(String trackId) async {
    final t = downloaded.where((d) => d.id == trackId).firstOrNull;
    if (t == null) return;
    downloaded.removeWhere((d) => d.id == trackId);
    for (final uri in [t.sourceUri, t.artUri]) {
      if (uri == null) continue;
      try {
        final f = File.fromUri(Uri.parse(uri));
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await _saveIndex();
    notifyListeners();
  }

  Future<void> _saveIndex() async {
    final list = downloaded
        .map((t) => {
              'id': t.id,
              'title': t.title,
              'artist': t.artist,
              'album': t.album,
              'filePath': t.filePath,
              'trackNumber': t.trackNumber,
              'discNumber': t.discNumber,
              'duration': t.duration,
              'sourceUri': t.sourceUri,
              'artUri': t.artUri,
            })
        .toList();
    await _indexFile.writeAsString(jsonEncode(list));
  }

  Track? _fromIndex(Map<String, dynamic> j) {
    final sourceUri = j['sourceUri']?.toString();
    if (sourceUri == null) return null;
    try {
      // Drop index entries whose file was cleared (e.g. by Android storage cleanup).
      if (!File.fromUri(Uri.parse(sourceUri)).existsSync()) return null;
    } catch (_) {
      return null;
    }
    return Track(
      id: (j['id'] ?? sourceUri).toString(),
      title: (j['title'] ?? 'Unknown').toString(),
      artist: (j['artist'] ?? 'Unknown Artist').toString(),
      album: j['album']?.toString(),
      filePath: (j['filePath'] ?? '').toString(),
      trackNumber: (j['trackNumber'] as num?)?.toInt() ?? 0,
      discNumber: (j['discNumber'] as num?)?.toInt() ?? 1,
      duration: (j['duration'] as num?)?.toDouble() ?? 0,
      sourceUri: sourceUri,
      artUri: j['artUri']?.toString(),
    );
  }

  static String _safeName(String id) =>
      id.replaceAll(RegExp(r'[^\w.-]'), '_').replaceAll(RegExp(r'_+'), '_');

  static String _ext(String path) {
    final m = RegExp(r'\.(\w{1,5})$').firstMatch(path);
    return m != null ? '.${m.group(1)}' : '.audio';
  }
}
