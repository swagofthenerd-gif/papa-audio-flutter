import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'text_norm.dart';

/// User-tunable behavior, persisted with shared_preferences. Kept intentionally
/// small: every entry here must be surfaced in the settings screen.
class SettingsService extends ChangeNotifier {
  SharedPreferences? _prefs;

  // Playback
  bool playPauseFade = true;
  int fadeMs = 300;
  bool skipSilence = false;
  bool linkSpeedPitch = false;

  /// Seconds of fade-out before a track ends / fade-in after it changes.
  /// 0 = off. (True overlapping crossfade needs a second player, which the
  /// background-audio plugin forbids — this is the single-player version.)
  int transitionFadeSec = 0;

  /// Tint the expanded player with the current artwork's dominant color.
  bool dynamicColors = true;

  // Listen counting: fixed seconds, or a percentage of the track's duration.
  int listenSeconds = 20;
  bool listenPercentMode = false;
  int listenPercent = 20;

  /// Skipping with next/previous while paused also starts playback.
  bool playOnSkip = false;

  /// Seconds jumped per hop while holding the prev/next transport buttons.
  int holdSeekSec = 5;

  /// Track tiles show "Artist" as the main line with the title beneath.
  bool artistBeforeTitle = false;

  // Track tile swipes: what left/right swipe do (indices into SwipeAction).
  SwipeAction swipeRight = SwipeAction.playNext;
  SwipeAction swipeLeft = SwipeAction.addToQueue;

  // What tapping a track does to the queue.
  TapMode tapMode = TapMode.list;

  // Album grid density in the library (2 or 3 columns).
  int gridColumns = 2;

  /// When the queue finishes (repeat off): return to the first track, paused,
  /// instead of staying stopped at the end.
  bool queueEndRestart = false;

  // Multi-value tag splitting (Artists / Genres tabs). Conservative defaults —
  // '&' and '/' split legitimate names too often, so they're opt-in.
  List<String> artistSeparators = [';', ' feat. ', ' ft. ', ' featuring '];
  List<String> genreSeparators = [';', '/', ','];
  List<String> splitBlacklist = ['AC/DC'];

  TagSplitter? _artistSplitter;
  TagSplitter? _genreSplitter;
  TagSplitter get artistSplitter => _artistSplitter ??= TagSplitter(
      separators: artistSeparators, blacklist: splitBlacklist.toSet());
  TagSplitter get genreSplitter => _genreSplitter ??= TagSplitter(
      separators: genreSeparators, blacklist: splitBlacklist.toSet());

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
    gridColumns = (p.getInt('s.gridColumns') ?? 2).clamp(2, 3);
    queueEndRestart = p.getBool('s.queueEndRestart') ?? false;
    listenPercentMode = p.getBool('s.listenPercentMode') ?? false;
    listenPercent = (p.getInt('s.listenPercent') ?? 20).clamp(5, 90);
    playOnSkip = p.getBool('s.playOnSkip') ?? false;
    holdSeekSec = (p.getInt('s.holdSeekSec') ?? 5).clamp(1, 60);
    artistBeforeTitle = p.getBool('s.artistBeforeTitle') ?? false;
    transitionFadeSec = p.getInt('s.transitionFadeSec') ?? 0;
    dynamicColors = p.getBool('s.dynamicColors') ?? true;
    artistSeparators = p.getStringList('s.artistSeps') ?? artistSeparators;
    genreSeparators = p.getStringList('s.genreSeps') ?? genreSeparators;
    splitBlacklist = p.getStringList('s.splitBlacklist') ?? splitBlacklist;
    // Drop any splitter built from defaults before persisted separators loaded,
    // and bump revision so splitter-memoized groupings recompute.
    _artistSplitter = null;
    _genreSplitter = null;
    revision++;
    notifyListeners();
  }

  /// Bumped on every change — lets views memoize splitter-derived groupings.
  int revision = 0;

  void update(void Function() change) {
    change();
    _artistSplitter = null; // separator/blacklist edits rebuild the splitters
    _genreSplitter = null;
    revision++;
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
    p.setInt('s.gridColumns', gridColumns);
    p.setBool('s.queueEndRestart', queueEndRestart);
    p.setBool('s.listenPercentMode', listenPercentMode);
    p.setInt('s.listenPercent', listenPercent);
    p.setBool('s.playOnSkip', playOnSkip);
    p.setInt('s.holdSeekSec', holdSeekSec);
    p.setBool('s.artistBeforeTitle', artistBeforeTitle);
    p.setInt('s.transitionFadeSec', transitionFadeSec);
    p.setBool('s.dynamicColors', dynamicColors);
    p.setStringList('s.artistSeps', artistSeparators);
    p.setStringList('s.genreSeps', genreSeparators);
    p.setStringList('s.splitBlacklist', splitBlacklist);
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
