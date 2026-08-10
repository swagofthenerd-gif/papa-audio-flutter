import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Manages volume swipe gestures on the player screen.
/// Right-half vertical swipe adjusts system volume, with an overlay UI.
class VolumeBrightnessController extends ChangeNotifier {
  double _volume = 0.5;

  double get volume => _volume;

  bool _showing = false;
  bool get showing => _showing;

  double _startVolume = 0;

  void onDragStart() {
    _startVolume = _volume;
    _showing = true;
    notifyListeners();
  }

  void onDragUpdate(double fraction) {
    _volume = (_startVolume - fraction).clamp(0.0, 1.0);
    SystemChannels.platform.invokeMethod('SystemChrome.setVolume', _volume);
    _showing = true;
    notifyListeners();
  }

  Future<void> onDragEnd() async {
    await Future.delayed(const Duration(milliseconds: 800));
    _showing = false;
    notifyListeners();
  }

  Future<void> fetchCurrentLevels() async {
    try {
      final vol = await SystemChannels.platform
          .invokeMethod<double>('SystemChrome.getVolume');
      _volume = vol ?? 0.5;
      notifyListeners();
    } catch (_) {}
  }
}

/// A small overlay bar that appears while the user is adjusting volume
/// via vertical swipe gesture on the right side of the player.
class VolumeBrightnessOverlay extends StatelessWidget {
  final VolumeBrightnessController controller;
  const VolumeBrightnessOverlay({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) {
        if (!controller.showing) return const SizedBox.shrink();
        final v = controller.volume;
        final icon = v == 0
            ? Icons.volume_off
            : v < 0.5
                ? Icons.volume_down
                : Icons.volume_up;
        return Positioned(
          top: MediaQuery.sizeOf(context).height * 0.10,
          right: 32,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: controller.showing ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 52,
                height: 190,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: Colors.white, size: 28),
                    const SizedBox(height: 10),
                    RotatedBox(
                      quarterTurns: -1,
                      child: SizedBox(
                        width: 130,
                        height: 14,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: LinearProgressIndicator(
                            value: v,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation(Colors.white),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('${(v * 100).round()}%',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
