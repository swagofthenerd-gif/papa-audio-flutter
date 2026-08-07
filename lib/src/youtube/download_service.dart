import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Downloads YouTube audio to the device.
class YouTubeDownloadService {
  final YouTubeService _yt;
  final Map<String, _DownloadJob> _jobs = {};

  YouTubeDownloadService(this._yt);

  /// Start downloading audio for a video. Returns a stream of progress (0.0-1.0).
  Stream<double> download(String videoId, String title) {
    final controller = StreamController<double>.broadcast();
    _jobs[videoId] = _DownloadJob(
      videoId: videoId,
      title: title,
      controller: controller,
    );
    _runDownload(videoId);
    return controller.stream;
  }

  Future<void> _runDownload(String videoId) async {
    final job = _jobs[videoId];
    if (job == null) return;

    try {
      job.controller.add(0.0);

      // Get the audio stream URL
      final url = await _yt.getAudioStreamUrl(videoId);
      if (url == null) {
        job.controller.addError('No audio stream available');
        return;
      }

      // Download to temp file
      final dir = await getApplicationDocumentsDirectory();
      final dlDir = Directory('${dir.path}/youtube_downloads');
      if (!dlDir.existsSync()) dlDir.createSync(recursive: true);

      final safeName = job.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File('${dlDir.path}/$safeName.m4a');

      final httpClient = HttpClient();
      final request = await httpClient.getUrl(Uri.parse(url));
      final response = await request.close();

      final totalBytes = response.contentLength;
      var downloadedBytes = 0;

      final sink = file.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        if (totalBytes > 0) {
          job.controller.add(downloadedBytes / totalBytes);
        }
      }
      await sink.close();
      httpClient.close();

      job.filePath = file.path;
      job.controller.add(1.0);
      job.controller.close();
    } catch (e) {
      job.controller.addError(e);
    }
  }

  /// Cancel a download.
  void cancel(String videoId) {
    _jobs[videoId]?.controller.close();
    _jobs.remove(videoId);
  }

  /// Get download progress.
  double? progress(String videoId) => _jobs[videoId]?.controller != null
      ? null // stream-based, use the stream directly
      : null;

  /// Check if a video is currently downloading.
  bool isDownloading(String videoId) => _jobs.containsKey(videoId);

  /// Get the downloaded file path once complete.
  String? filePath(String videoId) => _jobs[videoId]?.filePath;

  void dispose() {
    for (final job in _jobs.values) {
      job.controller.close();
    }
    _jobs.clear();
  }
}

class _DownloadJob {
  final String videoId;
  final String title;
  final StreamController<double> controller;
  String? filePath;

  _DownloadJob({
    required this.videoId,
    required this.title,
    required this.controller,
  });
}

// Re-export models for convenience
export 'models.dart';
