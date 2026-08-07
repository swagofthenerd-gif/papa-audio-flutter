import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Zero-config crash logger that writes every unhandled error to disk.
///
/// Usage in main():
/// ```dart
/// WidgetsFlutterBinding.ensureInitialized();
/// CrashLogger.init();
/// FlutterError.onError = CrashLogger.onFlutterError;
/// PlatformDispatcher.instance.onError = CrashLogger.onPlatformError;
/// ```
class CrashLogger {
  static final List<_Entry> _buffer = [];
  static File? _file;
  static bool _initialised = false;
  static Timer? _flushTimer;

  // ── Init ──────────────────────────────────────────────────────────────

  static Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/papa_crash.log');
      // Rotate if > 512 KB
      if (await _file!.exists() && await _file!.length() > 512 * 1024) {
        await _file!.rename('${dir.path}/papa_crash.old.log');
        _file = File('${dir.path}/papa_crash.log');
      }
    } catch (_) {
      _file = null;
    }
    // Periodic flush every 5 seconds so we don't lose crashes on hard kill.
    _flushTimer = Timer.periodic(const Duration(seconds: 5), (_) => flush());
  }

  // ── Hooks ─────────────────────────────────────────────────────────────

  static void onFlutterError(FlutterErrorDetails details) {
    log(
      type: 'FLUTTER',
      message: details.exceptionAsString(),
      stack: details.stack?.toString() ?? StackTrace.current.toString(),
    );
    // Still let the framework paint the red screen / banner in debug.
    FlutterError.presentError(details);
  }

  static bool onPlatformError(Object error, StackTrace stack) {
    log(type: 'PLATFORM', message: error.toString(), stack: stack.toString());
    return true; // handled
  }

  // ── Public API ────────────────────────────────────────────────────────

  /// Log an error manually from anywhere in the app.
  static void log({
    String type = 'MANUAL',
    required String message,
    String? stack,
    Map<String, String>? extra,
  }) {
    final entry = _Entry(
      timestamp: DateTime.now(),
      type: type,
      message: message,
      stack: stack,
      extra: extra,
    );
    _buffer.add(entry);
    // Also print so `adb logcat` / IDE console still sees it.
    debugPrint('[CrashLogger/$type] $message');
    if (stack != null) debugPrint(stack);
    // Flush after serious errors.
    if (type == 'PLATFORM' || type == 'FLUTTER') flush();
  }

  /// Safe wrapper for async operations — catches and logs errors silently.
  static Future<T?> guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (e, st) {
      log(type: 'GUARD', message: e.toString(), stack: st.toString());
      return null;
    }
  }

  /// Writes buffered entries to disk.
  static Future<void> flush() async {
    if (_buffer.isEmpty || _file == null) return;
    final batch = _buffer.toList();
    _buffer.clear();
    try {
      final sink = _file!.openWrite(mode: FileMode.append);
      for (final e in batch) {
        sink.writeln(jsonEncode(e.toJson()));
      }
      await sink.flush();
      await sink.close();
    } catch (_) {}
  }

  /// List of crash entries for a diagnostics screen.
  static Future<List<_Entry>> loadAll() async {
    if (_file == null || !await _file!.exists()) return [];
    try {
      final lines = await _file!.readAsLines();
      return lines
          .map((l) {
            try {
              return _Entry.fromJson(jsonDecode(l) as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<_Entry>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Path to the crash log file, or null if unavailable.
  static Future<String?> filePath() async {
    if (_file != null) return _file!.path;
    try {
      final dir = await getApplicationDocumentsDirectory();
      return '${dir.path}/papa_crash.log';
    } catch (_) {
      return null;
    }
  }

  /// Share the crash log via the OS share sheet.
  static Future<void> shareLog() async {
    final path = await filePath();
    if (path == null || !File(path).existsSync()) return;
    await Share.shareXFiles([XFile(path, mimeType: 'text/plain')],
        subject: 'Papa Audio Crash Log');
  }

  /// Clear the crash log.
  static Future<void> clearLog() async {
    _buffer.clear();
    try {
      await _file?.delete();
    } catch (_) {}
  }
}

// ── Entry model ───────────────────────────────────────────────────────────

class _Entry {
  final DateTime timestamp;
  final String type;
  final String message;
  final String? stack;
  final Map<String, String>? extra;

  _Entry({
    required this.timestamp,
    required this.type,
    required this.message,
    this.stack,
    this.extra,
  });

  Map<String, dynamic> toJson() => {
        'ts': timestamp.toIso8601String(),
        'type': type,
        'msg': message,
        if (stack != null) 'stack': stack,
        if (extra != null) 'extra': extra,
      };

  factory _Entry.fromJson(Map<String, dynamic> j) => _Entry(
        timestamp: DateTime.parse(j['ts'] as String),
        type: j['type'] as String? ?? '?',
        message: j['msg'] as String? ?? '',
        stack: j['stack'] as String?,
        extra: (j['extra'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v.toString())),
      );
}
