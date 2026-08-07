import 'dart:async';
import 'package:flutter/services.dart';

/// Keeps the screen awake based on context (player expanded, video, lyrics).
class WakelockController {
  WakelockController._();
  static final WakelockController inst = WakelockController._();

  static const _channel = MethodChannel('com.example.papa_audio/wakelock');

  bool _enabled = false;
  bool _playerExpanded = false;
  bool _lyricsVisible = false;

  WakelockMode _mode = WakelockMode.expandedAndLyrics;
  WakelockMode get mode => _mode;
  set mode(WakelockMode v) {
    _mode = v;
    _refresh();
  }

  void setPlayerExpanded(bool v) { _playerExpanded = v; _refresh(); }
  void setLyricsVisible(bool v) { _lyricsVisible = v; _refresh(); }

  Future<void> _refresh() async {
    bool shouldLock = false;
    switch (_mode) {
      case WakelockMode.always:
        shouldLock = true;
        break;
      case WakelockMode.expanded:
        shouldLock = _playerExpanded;
        break;
      case WakelockMode.expandedAndLyrics:
        shouldLock = _playerExpanded || _lyricsVisible;
        break;
      case WakelockMode.never:
        shouldLock = false;
        break;
    }
    if (shouldLock != _enabled) {
      _enabled = shouldLock;
      try {
        await _channel.invokeMethod(shouldLock ? 'enable' : 'disable');
      } catch (_) {}
    }
  }

  void dispose() { _enabled = false; _refresh(); }
}

enum WakelockMode { always, expanded, expandedAndLyrics, never }
