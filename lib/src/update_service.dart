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

  /// Fetch releases and, if any has a higher build than [kAppBuildNumber],
  /// expose the highest one via [available]. Runs at most once per app session;
  /// silent on failure.
  ///
  /// NB: we deliberately do NOT use `/releases/latest`. That endpoint sorts by
  /// `created_at`, and CI-published releases can inherit an older tag/commit
  /// date than a hand-made release — so `/latest` may point at an older build
  /// than one that exists. Listing all releases and taking the max tag number
  /// is robust against that ordering quirk.
  Future<void> checkForUpdate({bool force = false}) async {
    if (_checked && !force) return;
    _checked = true;
    lastError = null;
    try {
      final resp = await http
          .get(
            Uri.parse(
                'https://api.github.com/repos/$_repo/releases?per_page=30'),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) {
        lastError = resp.statusCode == 403
            ? 'GitHub rate-limited this check. Try again in a few minutes.'
            : 'Update check failed (HTTP ${resp.statusCode}).';
        return;
      }
      final releases = (jsonDecode(resp.body) as List).whereType<Map>();
      // Pick the release with the highest build number (parsed from its tag)
      // that isn't a draft/prerelease.
      Map? best;
      var bestBuild = kAppBuildNumber;
      for (final r in releases) {
        if (r['draft'] == true || r['prerelease'] == true) continue;
        final tag = (r['tag_name'] ?? '').toString();
        final build = int.tryParse(tag.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        if (build > bestBuild) {
          bestBuild = build;
          best = r;
        }
      }
      if (best == null) return; // already on the newest build
      final tag = (best['tag_name'] ?? '').toString();
      final assets = (best['assets'] as List?) ?? const [];
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
        buildNumber: bestBuild,
        versionName: tag.replaceFirst(RegExp(r'^v'), ''),
        notes: (best['body'] ?? '').toString().trim(),
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
