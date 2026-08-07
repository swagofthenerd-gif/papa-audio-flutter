import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Provides volume and brightness swipe gestures on the player sheet.
/// Swipe left/right = seek, swipe up/down left half = brightness,
/// swipe up/down right half = volume.
class VolumeBrightnessGestureController {
  static final VolumeBrightnessGestureController instance =
      VolumeBrightnessGestureController._();
  VolumeBrightnessGestureController._();

  /// Current volume level (0.0 - 1.0)
  double get volume => _volume;
  double _volume = 0.5;

  /// Current brightness level (0.0 - 1.0)
  double get brightness => _brightness;
  double _brightness = 0.5;

  /// Whether to show the volume HUD
  bool showVolumeHud = false;

  /// Whether to show the brightness HUD
  bool showBrightnessHud = false;

  /// Update volume from a swipe delta
  void updateVolume(double delta, BuildContext context) {
    _volume = (_volume + delta).clamp(0.0, 1.0);
    showVolumeHud = true;
    SystemChannels.volume.invokeMethod('setVolume', _volume);
    // Auto-hide HUD after 1s
    Future.delayed(const Duration(seconds: 1), () {
      showVolumeHud = false;
    });
  }

  /// Update brightness from a swipe delta
  void updateBrightness(double delta) {
    _brightness = (_brightness + delta).clamp(0.0, 1.0);
    showBrightnessHud = true;
    // Auto-hide HUD after 1s
    Future.delayed(const Duration(seconds: 1), () {
      showBrightnessHud = false;
    });
  }
}

/// Volume HUD overlay widget
class VolumeHud extends StatelessWidget {
  final double level;
  const VolumeHud({super.key, required this.level});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              level == 0 ? Icons.volume_off : Icons.volume_up,
              color: Colors.white,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              '${(level * 100).round()}%',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

/// Brightness HUD overlay widget
class BrightnessHud extends StatelessWidget {
  final double level;
  const BrightnessHud({super.key, required this.level});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.brightness_6, color: Colors.white, size: 32),
            const SizedBox(height: 8),
            Text(
              '${(level * 100).round()}%',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
