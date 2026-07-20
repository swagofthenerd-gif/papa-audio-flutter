import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'version.dart';

/// An available newer release discovered on GitHub.
class UpdateInfo {
  final int buildNumber;
  final String versionName; // release tag, cleaned
  final String notes; // release body / changelog
  final String apkUrl;
  final int? sizeBytes;
  const UpdateInfo({
    required this.buildNumber,
    required this.versionName,
    required this.notes,
    required this.apkUrl,
    this.sizeBytes,
  });
}

/// Checks GitHub Releases for a newer build and installs it in-app, so the
/// user never has to sideload manually. Distribution channel: the project's
/// own GitHub releases (each tagged `v<buildNumber>` with the APK attached).
class UpdateService extends ChangeNotifier {
  static const _repo = 'swagofthenerd-gif/papa-audio-flutter';
  static const _ch = MethodChannel('papa.audio/media_store');

  /// Set when a newer release is found. Drives the update dialog.
  UpdateInfo? available;

  /// 0..1 while downloading; null when idle.
  double? downloadProgress;

  /// Why the last check found nothing — surfaced by the manual "Check for
  /// updates" action so a silent failure (offline, rate-limited, exception)
  /// is distinguishable from genuinely being up to date. null after a clean
  /// check that simply found no newer build.
  String? lastError;
  bool _checked = false;

  /// Fetch the latest release and, if newer than [kAppBuildNumber], expose it
  /// via [available]. Runs at most once per app session; silent on failure.
  Future<void> checkForUpdate({bool force = false}) async {
    if (_checked && !force) return;
    _checked = true;
    lastError = null;
    try {
      final resp = await http
          .get(
            Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) {
        lastError = resp.statusCode == 403
            ? 'GitHub rate-limited this check. Try again in a few minutes.'
            : 'Update check failed (HTTP ${resp.statusCode}).';
        return;
      }
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final tag = (json['tag_name'] ?? '').toString();
      final build = int.tryParse(tag.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (build <= kAppBuildNumber) return;
      final assets = (json['assets'] as List?) ?? const [];
      final apk = assets.whereType<Map>().firstWhere(
            (a) => (a['name'] ?? '').toString().toLowerCase().endsWith('.apk'),
            orElse: () => const {},
          );
      final apkUrl = apk['browser_download_url']?.toString();
      if (apkUrl == null) {
        lastError = 'Release $tag has no APK attached yet.';
        return;
      }
      available = UpdateInfo(
        buildNumber: build,
        versionName: tag.replaceFirst(RegExp(r'^v'), ''),
        notes: (json['body'] ?? '').toString().trim(),
        apkUrl: apkUrl,
        sizeBytes: (apk['size'] as num?)?.toInt(),
      );
      notifyListeners();
    } catch (e) {
      // Offline / rate-limited / no releases — stay quiet in the auto-check,
      // but record why so the manual check can explain the failure.
      lastError = e is TimeoutException
          ? 'Update check timed out. Check your connection.'
          : 'Update check failed — no connection?';
    }
  }

  /// Download the update APK (reporting [downloadProgress]) and hand it to the
  /// system installer. Throws on failure so the dialog can surface it.
  Future<void> downloadAndInstall() async {
    final info = available;
    if (info == null) return;
    downloadProgress = 0;
    notifyListeners();

    final dir = await getExternalStorageDirectory() ??
        await getApplicationCacheDirectory();
    final updatesDir = Directory('${dir.path}/updates');
    if (!updatesDir.existsSync()) updatesDir.createSync(recursive: true);
    final file = File('${updatesDir.path}/papa-audio-${info.buildNumber}.apk');

    final client = http.Client();
    IOSink? sink;
    try {
      final req = http.Request('GET', Uri.parse(info.apkUrl));
      final resp =
          await client.send(req).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        throw 'Download failed (HTTP ${resp.statusCode})';
      }
      final total = resp.contentLength ?? info.sizeBytes ?? 0;
      var received = 0;
      sink = file.openWrite();
      // A stalled connection mid-body must not hang the updater forever.
      await for (final chunk
          in resp.stream.timeout(const Duration(seconds: 60))) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          downloadProgress = (received / total).clamp(0.0, 1.0);
          notifyListeners();
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
    } finally {
      // On any failure: close the sink, reset progress so the dialog isn't
      // stuck, and free the socket. (installApk below only runs on success —
      // a thrown error skips past it.)
      try {
        await sink?.close();
      } catch (_) {}
      client.close();
      downloadProgress = null;
      notifyListeners();
    }

    await _ch.invokeMethod('installApk', {'path': file.path});
  }

  /// User dismissed the prompt for this session.
  void dismiss() {
    available = null;
    notifyListeners();
  }
}
