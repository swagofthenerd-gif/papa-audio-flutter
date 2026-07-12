import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-tunable behavior, persisted with shared_preferences. Kept intentionally
/// small: every entry here must be surfaced in the settings screen.
class SettingsService extends ChangeNotifier {
  SharedPreferences? _prefs;

  // Playback
  bool playPauseFade = true;
  int fadeMs = 300;
  bool skipSilence = false;
  bool linkSpeedPitch = false;

  // Listen counting
  int listenSeconds = 20;

  // Track tile swipes: what left/right swipe do (indices into SwipeAction).
  SwipeAction swipeRight = SwipeAction.playNext;
  SwipeAction swipeLeft = SwipeAction.addToQueue;

  // What tapping a track does to the queue.
  TapMode tapMode = TapMode.list;

  Future<void> init() async {
    final p = _prefs = await SharedPreferences.getInstance();
    playPauseFade = p.getBool('s.fade') ?? true;
    fadeMs = p.getInt('s.fadeMs') ?? 300;
    skipSilence = p.getBool('s.skipSilence') ?? false;
    linkSpeedPitch = p.getBool('s.linkSpeedPitch') ?? false;
    listenSeconds = p.getInt('s.listenSeconds') ?? 20;
    swipeRight = SwipeAction.values[
        (p.getInt('s.swipeRight') ?? SwipeAction.playNext.index)
            .clamp(0, SwipeAction.values.length - 1)];
    swipeLeft = SwipeAction.values[
        (p.getInt('s.swipeLeft') ?? SwipeAction.addToQueue.index)
            .clamp(0, SwipeAction.values.length - 1)];
    tapMode = TapMode.values[(p.getInt('s.tapMode') ?? TapMode.list.index)
        .clamp(0, TapMode.values.length - 1)];
    notifyListeners();
  }

  void update(void Function() change) {
    change();
    notifyListeners();
    final p = _prefs;
    if (p == null) return;
    p.setBool('s.fade', playPauseFade);
    p.setInt('s.fadeMs', fadeMs);
    p.setBool('s.skipSilence', skipSilence);
    p.setBool('s.linkSpeedPitch', linkSpeedPitch);
    p.setInt('s.listenSeconds', listenSeconds);
    p.setInt('s.swipeRight', swipeRight.index);
    p.setInt('s.swipeLeft', swipeLeft.index);
    p.setInt('s.tapMode', tapMode.index);
  }
}

enum TapMode {
  list('Play the whole list'),
  single('Play only that track'),
  gentle('Gentle — insert into the current queue');

  final String label;
  const TapMode(this.label);
}

enum SwipeAction {
  playNext('Play next'),
  addToQueue('Add to queue'),
  favorite('Toggle favorite'),
  openMenu('Open menu');

  final String label;
  const SwipeAction(this.label);
}
