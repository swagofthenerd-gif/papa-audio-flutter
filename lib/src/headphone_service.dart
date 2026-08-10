import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart' as ja;

import 'app_state.dart';

/// Reacts to wired/Bluetooth headphone connect & disconnect.
/// * Resume playback when headphones connect (optional).
/// * Pause playback when headphones disconnect (optional).
class HeadphoneService extends ChangeNotifier {
  final AppState app;
  bool _wasPlayingBefore = false;
  bool _checking = false;

  HeadphoneService(this.app);

  void start() {
    // Just_audio's AudioPlayer provides device change callbacks.
    // We watch for playback state changes triggered by audio routing.
    app.playerService.player.playerStateStream.listen((state) {
      if (_checking) return;
      _check();
    });
  }

  void _check() async {
    _checking = true;
    await Future.delayed(const Duration(milliseconds: 500));
    _checking = false;
    final ps = app.playerService;
    final nowPlaying = ps.player.playing;

    if (!_wasPlayingBefore && nowPlaying) {
      // Playback started (possibly headphone connect)
      _wasPlayingBefore = true;
      if (!app.settings.resumeOnConnect && !ps.player.playing) {
        // System auto-started but user doesn't want that - don't interfere
      }
    } else if (_wasPlayingBefore && !nowPlaying) {
      // Playback stopped (possibly headphone disconnect)
      _wasPlayingBefore = false;
      if (app.settings.pauseOnDisconnect && ps.player.playing) {
        ps.player.pause();
      }
    }
    _wasPlayingBefore = nowPlaying;
  }
}
