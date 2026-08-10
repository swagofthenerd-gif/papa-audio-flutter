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

  // Last.fm
  String? lastFmApiKey = '3a74e7f5a3b0d7c4e9f6a8b2c1d0e5f7';
  String? lastFmSecret = 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6';
  String? lastFmSessionKey;
  String? lastFmUsername;

  // OLED / theme
  bool oledTheme = false;

  // Headphone actions
  bool resumeOnConnect = true;
  bool pauseOnDisconnect = true;

  // Player extras
  bool showRemainingTime = false;
  bool showUpNext = true;

  // Indexer
  List<String> libraryFolders = ['/storage/emulated/0/Music'];
  bool respectNomedia = true;
  int minTrackDurationSec = 5;
  int minTrackSizeKB = 100;
  bool useMediaStore = true;
  bool refreshOnStartup = false;
  bool skipSymbolicLinks = true;
  bool scanHiddenFolders = false;
  bool preferEmbeddedArt = true;
  int maxArtworkSizeKB = 500;
  bool scanOnMounted = true;
  int scanIntervalMinutes = 0;
  int indexerConcurrency = 4;
  List<String> albumIdentifiers = ['album', 'album_artist', 'disc_number'];
  bool indexerLogging = false;

  // Customization
  String tileLayoutConfig = 'title,artist,duration';
  bool showTrackNumbers = true;
  double albumTileSize = 160.0;
  bool forceSquareThumbnails = false;
  bool staggeredAlbumGrid = false;
  bool gradientTiles = true;
  bool tiltingCards = false;
  bool floatingArtworkEffect = false;
  int waveformBars = 80;
  double waveformHeight = 48.0;
  bool showWaveform = true;
  double fontScale = 1.0;
  bool compactMode = false;
  bool showAlbumDates = true;
  String dateFormat = 'MMM d, yyyy';
  bool hourFormat24 = false;
  bool showDividerLines = true;
  double lyricFontSize = 18.0;
  bool showPlainLyricsByDefault = false;
  String albumPageSortOrder = 'track_number';
  String defaultLibraryTab = 'tracks';
  bool expandedSearchbarAlways = false;

  // Theme
  int accentColorIndex = 0;
  bool dynamicArtworkColors = true;
  String animatingThumbnailIntensity = 'full';

  // Playback extras
  double countListenAfterPercent = 50.0;
  String onVolumeZero = 'nothing';
  String onAudioInterruption = 'pause';
  bool previousButtonReplays = true;
  bool infinityQueueNextPrev = false;
  bool jumpToFirstAfterFinish = false;
  int minDurationToResumeSec = 300;
  bool collectionResume = true;
  int resumeThresholdSeconds = 30;
  bool keepAwake = false;
  String killPolicy = 'after_notification_swipe';
  int killAfterIdleMinutes = 30;
  String notificationConfig = 'always';
  bool perTrackAudioOverride = false;

  // Extra UI
  String fabAction = 'shuffle_all';
  String vibrationType = 'haptic';
  bool mediaWaveHaptic = false;
  bool partyMode = false;
  bool partyModeAnimatedGradient = true;
  int edgeColorsSwitchInterval = 8;
  String artworkTapAction = 'toggle_lyrics';
  String artworkLongPressAction = 'track_info';
  String trackPlayMode = 'selected';
  String playlistAddPosition = 'end';
  bool mixedQueueEnabled = true;
  bool clipboardMonitoring = false;

  // Backup & Advanced
  bool backupEnabled = false;
  int autoBackupIntervalDays = 7;
  String backupLocation = '/storage/emulated/0/PapaAudio/backups';
  int backupMaxCount = 5;
  int imageCacheMaxMB = 100;
  int waveformCacheMaxMB = 50;
  bool performanceMode = false;
  bool compressImages = false;
  bool animationsEnabled = true;
  bool debugLogging = false;

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
    lastFmSessionKey = p.getString('s.lastFmKey');
    lastFmUsername = p.getString('s.lastFmUser');
    oledTheme = p.getBool('s.oled') ?? false;
    resumeOnConnect = p.getBool('s.resumeOnConn') ?? true;
    pauseOnDisconnect = p.getBool('s.pauseOnDisc') ?? true;
    showRemainingTime = p.getBool('s.showRemaining') ?? false;
    showUpNext = p.getBool('s.showUpNext') ?? true;
    // Indexer
    libraryFolders = p.getStringList('s.libFolders') ?? libraryFolders;
    respectNomedia = p.getBool('s.nomedia') ?? true;
    minTrackDurationSec = p.getInt('s.minDur') ?? 5;
    minTrackSizeKB = p.getInt('s.minSize') ?? 100;
    useMediaStore = p.getBool('s.useMediaStore') ?? true;
    refreshOnStartup = p.getBool('s.refreshStartup') ?? false;
    skipSymbolicLinks = p.getBool('s.skipSymlinks') ?? true;
    scanHiddenFolders = p.getBool('s.scanHidden') ?? false;
    preferEmbeddedArt = p.getBool('s.prefEmbedArt') ?? true;
    maxArtworkSizeKB = p.getInt('s.maxArtKB') ?? 500;
    scanOnMounted = p.getBool('s.scanOnMount') ?? true;
    scanIntervalMinutes = p.getInt('s.scanInterval') ?? 0;
    indexerConcurrency = p.getInt('s.idxConcurrency') ?? 4;
    albumIdentifiers = p.getStringList('s.albumIds') ?? albumIdentifiers;
    indexerLogging = p.getBool('s.idxLog') ?? false;
    // Customization
    tileLayoutConfig = p.getString('s.tileLayout') ?? tileLayoutConfig;
    showTrackNumbers = p.getBool('s.showTrackNums') ?? true;
    albumTileSize = p.getDouble('s.albumTileSize') ?? 160.0;
    forceSquareThumbnails = p.getBool('s.forceSquare') ?? false;
    staggeredAlbumGrid = p.getBool('s.staggered') ?? false;
    gradientTiles = p.getBool('s.gradientTiles') ?? true;
    tiltingCards = p.getBool('s.tiltCards') ?? false;
    floatingArtworkEffect = p.getBool('s.floatArt') ?? false;
    waveformBars = p.getInt('s.waveBars') ?? 80;
    waveformHeight = p.getDouble('s.waveH') ?? 48.0;
    showWaveform = p.getBool('s.showWave') ?? true;
    fontScale = p.getDouble('s.fontScale') ?? 1.0;
    compactMode = p.getBool('s.compact') ?? false;
    showAlbumDates = p.getBool('s.showAlbumDates') ?? true;
    dateFormat = p.getString('s.dateFmt') ?? dateFormat;
    hourFormat24 = p.getBool('s.hour24') ?? false;
    showDividerLines = p.getBool('s.showDividers') ?? true;
    lyricFontSize = p.getDouble('s.lyricFont') ?? 18.0;
    showPlainLyricsByDefault = p.getBool('s.plainLyrics') ?? false;
    albumPageSortOrder = p.getString('s.albumSort') ?? albumPageSortOrder;
    defaultLibraryTab = p.getString('s.defaultLibTab') ?? defaultLibraryTab;
    expandedSearchbarAlways = p.getBool('s.expandSearch') ?? false;
    // Theme
    accentColorIndex = p.getInt('s.accentIdx') ?? 0;
    dynamicArtworkColors = p.getBool('s.dynamicColors') ?? true;
    animatingThumbnailIntensity = p.getString('s.thumbIntensity') ?? 'full';
    // Playback extras
    countListenAfterPercent = p.getDouble('s.listenPct') ?? 50.0;
    onVolumeZero = p.getString('s.onVol0') ?? 'nothing';
    onAudioInterruption = p.getString('s.onInterrupt') ?? 'pause';
    previousButtonReplays = p.getBool('s.prevReplays') ?? true;
    infinityQueueNextPrev = p.getBool('s.infQueue') ?? false;
    jumpToFirstAfterFinish = p.getBool('s.jumpFirst') ?? false;
    minDurationToResumeSec = p.getInt('s.minResume') ?? 300;
    collectionResume = p.getBool('s.collectionResume') ?? true;
    resumeThresholdSeconds = p.getInt('s.resumeThresh') ?? 30;
    keepAwake = p.getBool('s.keepAwake') ?? false;
    killPolicy = p.getString('s.killPolicy') ?? 'after_notification_swipe';
    killAfterIdleMinutes = p.getInt('s.killIdle') ?? 30;
    notificationConfig = p.getString('s.notifConfig') ?? 'always';
    perTrackAudioOverride = p.getBool('s.perTrackOverride') ?? false;
    // Extra UI
    fabAction = p.getString('s.fabAction') ?? 'shuffle_all';
    vibrationType = p.getString('s.vibType') ?? 'haptic';
    mediaWaveHaptic = p.getBool('s.mediaWaveHaptic') ?? false;
    partyMode = p.getBool('s.partyMode') ?? false;
    partyModeAnimatedGradient = p.getBool('s.partyGrad') ?? true;
    edgeColorsSwitchInterval = p.getInt('s.edgeInterval') ?? 8;
    artworkTapAction = p.getString('s.artTap') ?? 'toggle_lyrics';
    artworkLongPressAction = p.getString('s.artLongPress') ?? 'track_info';
    trackPlayMode = p.getString('s.trackPlayMode') ?? 'selected';
    playlistAddPosition = p.getString('s.plAddPos') ?? 'end';
    mixedQueueEnabled = p.getBool('s.mixedQueue') ?? true;
    clipboardMonitoring = p.getBool('s.clipMon') ?? false;
    // Backup & Advanced
    backupEnabled = p.getBool('s.backupEnabled') ?? false;
    autoBackupIntervalDays = p.getInt('s.backupInterval') ?? 7;
    backupLocation = p.getString('s.backupLoc') ?? backupLocation;
    backupMaxCount = p.getInt('s.backupMax') ?? 5;
    imageCacheMaxMB = p.getInt('s.imgCacheMB') ?? 100;
    waveformCacheMaxMB = p.getInt('s.waveCacheMB') ?? 50;
    performanceMode = p.getBool('s.perfMode') ?? false;
    compressImages = p.getBool('s.compressImgs') ?? false;
    animationsEnabled = p.getBool('s.anims') ?? true;
    debugLogging = p.getBool('s.debugLog') ?? false;
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
    if (lastFmSessionKey != null) p.setString('s.lastFmKey', lastFmSessionKey!);
    if (lastFmUsername != null) p.setString('s.lastFmUser', lastFmUsername!);
    p.setBool('s.oled', oledTheme);
    p.setBool('s.resumeOnConn', resumeOnConnect);
    p.setBool('s.pauseOnDisc', pauseOnDisconnect);
    p.setBool('s.showRemaining', showRemainingTime);
    p.setBool('s.showUpNext', showUpNext);
    // Indexer
    p.setStringList('s.libFolders', libraryFolders);
    p.setBool('s.nomedia', respectNomedia);
    p.setInt('s.minDur', minTrackDurationSec);
    p.setInt('s.minSize', minTrackSizeKB);
    p.setBool('s.useMediaStore', useMediaStore);
    p.setBool('s.refreshStartup', refreshOnStartup);
    p.setBool('s.skipSymlinks', skipSymbolicLinks);
    p.setBool('s.scanHidden', scanHiddenFolders);
    p.setBool('s.prefEmbedArt', preferEmbeddedArt);
    p.setInt('s.maxArtKB', maxArtworkSizeKB);
    p.setBool('s.scanOnMount', scanOnMounted);
    p.setInt('s.scanInterval', scanIntervalMinutes);
    p.setInt('s.idxConcurrency', indexerConcurrency);
    p.setStringList('s.albumIds', albumIdentifiers);
    p.setBool('s.idxLog', indexerLogging);
    // Customization
    p.setString('s.tileLayout', tileLayoutConfig);
    p.setBool('s.showTrackNums', showTrackNumbers);
    p.setDouble('s.albumTileSize', albumTileSize);
    p.setBool('s.forceSquare', forceSquareThumbnails);
    p.setBool('s.staggered', staggeredAlbumGrid);
    p.setBool('s.gradientTiles', gradientTiles);
    p.setBool('s.tiltCards', tiltingCards);
    p.setBool('s.floatArt', floatingArtworkEffect);
    p.setInt('s.waveBars', waveformBars);
    p.setDouble('s.waveH', waveformHeight);
    p.setBool('s.showWave', showWaveform);
    p.setDouble('s.fontScale', fontScale);
    p.setBool('s.compact', compactMode);
    p.setBool('s.showAlbumDates', showAlbumDates);
    p.setString('s.dateFmt', dateFormat);
    p.setBool('s.hour24', hourFormat24);
    p.setBool('s.showDividers', showDividerLines);
    p.setDouble('s.lyricFont', lyricFontSize);
    p.setBool('s.plainLyrics', showPlainLyricsByDefault);
    p.setString('s.albumSort', albumPageSortOrder);
    p.setString('s.defaultLibTab', defaultLibraryTab);
    p.setBool('s.expandSearch', expandedSearchbarAlways);
    // Theme
    p.setInt('s.accentIdx', accentColorIndex);
    p.setBool('s.dynamicColors', dynamicArtworkColors);
    p.setString('s.thumbIntensity', animatingThumbnailIntensity);
    // Playback extras
    p.setDouble('s.listenPct', countListenAfterPercent);
    p.setString('s.onVol0', onVolumeZero);
    p.setString('s.onInterrupt', onAudioInterruption);
    p.setBool('s.prevReplays', previousButtonReplays);
    p.setBool('s.infQueue', infinityQueueNextPrev);
    p.setBool('s.jumpFirst', jumpToFirstAfterFinish);
    p.setInt('s.minResume', minDurationToResumeSec);
    p.setBool('s.collectionResume', collectionResume);
    p.setInt('s.resumeThresh', resumeThresholdSeconds);
    p.setBool('s.keepAwake', keepAwake);
    p.setString('s.killPolicy', killPolicy);
    p.setInt('s.killIdle', killAfterIdleMinutes);
    p.setString('s.notifConfig', notificationConfig);
    p.setBool('s.perTrackOverride', perTrackAudioOverride);
    // Extra UI
    p.setString('s.fabAction', fabAction);
    p.setString('s.vibType', vibrationType);
    p.setBool('s.mediaWaveHaptic', mediaWaveHaptic);
    p.setBool('s.partyMode', partyMode);
    p.setBool('s.partyGrad', partyModeAnimatedGradient);
    p.setInt('s.edgeInterval', edgeColorsSwitchInterval);
    p.setString('s.artTap', artworkTapAction);
    p.setString('s.artLongPress', artworkLongPressAction);
    p.setString('s.trackPlayMode', trackPlayMode);
    p.setString('s.plAddPos', playlistAddPosition);
    p.setBool('s.mixedQueue', mixedQueueEnabled);
    p.setBool('s.clipMon', clipboardMonitoring);
    // Backup & Advanced
    p.setBool('s.backupEnabled', backupEnabled);
    p.setInt('s.backupInterval', autoBackupIntervalDays);
    p.setString('s.backupLoc', backupLocation);
    p.setInt('s.backupMax', backupMaxCount);
    p.setInt('s.imgCacheMB', imageCacheMaxMB);
    p.setInt('s.waveCacheMB', waveformCacheMaxMB);
    p.setBool('s.perfMode', performanceMode);
    p.setBool('s.compressImgs', compressImages);
    p.setBool('s.anims', animationsEnabled);
    p.setBool('s.debugLog', debugLogging);
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
