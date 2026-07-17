import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import 'innertube.dart';

/// Drives the optional YouTube video overlay. Deliberately isolated from the
/// audio engine: it plays a *muxed* stream (audio+video in one URL) through its
/// own [VideoPlayerController], so there is never any cross-engine A/V sync.
///
/// Lifecycle: [open] a video (starting at [fromSec]); [close] returns the
/// position so the caller can resume just_audio there. Only one video is ever
/// live; opening another disposes the previous.
class YtVideoController extends ChangeNotifier {
  final Innertube tube;
  YtVideoController(this.tube);

  VideoPlayerController? _controller;
  String? _videoId;
  bool _loading = false;
  String? _error;

  VideoPlayerController? get controller => _controller;
  bool get loading => _loading;
  String? get error => _error;
  bool get ready => _controller?.value.isInitialized ?? false;

  /// Current playback position in seconds (0 when nothing is open).
  double get positionSec =>
      (_controller?.value.position.inMilliseconds ?? 0) / 1000.0;

  Future<void> open(String videoId, {double fromSec = 0}) async {
    if (_videoId == videoId && _controller != null) return;
    await _disposeController();
    _videoId = videoId;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final url = await tube.playerVideo(videoId);
      if (url == null) throw Exception('no video stream');
      // Bail if a newer open() superseded this one while resolving.
      if (_videoId != videoId) return;
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      await c.initialize();
      if (_videoId != videoId) {
        await c.dispose();
        return;
      }
      _controller = c;
      if (fromSec > 0) {
        await c.seekTo(Duration(milliseconds: (fromSec * 1000).round()));
      }
      await c.play();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Stop and tear down; returns the last position so audio can resume there.
  Future<double> close() async {
    final at = positionSec;
    await _disposeController();
    _videoId = null;
    notifyListeners();
    return at;
  }

  Future<void> _disposeController() async {
    final c = _controller;
    _controller = null;
    if (c != null) {
      try {
        await c.pause();
      } catch (_) {}
      try {
        await c.dispose();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }
}
