import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../settings.dart';
import '../theme.dart';
import '../../ui/widgets/backup_section.dart';
import 'dialogs.dart';
import 'equalizer_screen.dart';
import 'stats_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final st = s.settings;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: PA.background,
        title: const Text('Settings', style: TextStyle(fontSize: 17)),
      ),
      body: AnimatedBuilder(
        animation: st,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            // ── 1. Audio & Playback ──
            _ExpSection('Audio & Playback', [
              ListTile(
                leading: const Icon(Icons.equalizer, color: PA.textSecondary),
                title: const Text('Equalizer'),
                subtitle: const Text('Bands and loudness boost',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const EqualizerScreen())),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.waves, color: PA.textSecondary),
                title: const Text('Play/pause fade'),
                subtitle: Text('Volume ramps over ${st.fadeMs}ms',
                    style: const TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.playPauseFade,
                onChanged: (v) => st.update(() => st.playPauseFade = v),
              ),
              if (st.playPauseFade)
                Padding(
                  padding: const EdgeInsets.only(left: 68, right: 16),
                  child: _slider(context, 100, 1000, st.fadeMs.toDouble(),
                      label: '${st.fadeMs}ms',
                      onChanged: (v) => st.update(() => st.fadeMs = v.round())),
                ),
              ListTile(
                leading: const Icon(Icons.compare_arrows, color: PA.textSecondary),
                title: const Text('Transition fade'),
                subtitle: Text(
                    st.transitionFadeSec == 0
                        ? 'Off — tracks change instantly'
                        : 'Fades out/in over ${st.transitionFadeSec}s',
                    style: const TextStyle(color: PA.textMuted, fontSize: 12)),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 68, right: 16),
                child: _slider(context, 0, 10, st.transitionFadeSec.toDouble(),
                    label: st.transitionFadeSec == 0 ? 'Off' : '${st.transitionFadeSec}s',
                    partitions: 10,
                    onChanged: (v) => st.update(() => st.transitionFadeSec = v.round())),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.palette_outlined, color: PA.textSecondary),
                title: const Text('Dynamic player colors'),
                subtitle: const Text('Tint the player with artwork colors',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.dynamicArtworkColors,
                onChanged: (v) => st.update(() => st.dynamicArtworkColors = v),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.fast_forward, color: PA.textSecondary),
                title: const Text('Skip silence'),
                subtitle: const Text('Jump over silent stretches',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.skipSilence,
                onChanged: (v) {
                  st.update(() => st.skipSilence = v);
                  s.playerService.setSkipSilence(v);
                },
              ),
            ]),

            // ── 2. Speed & Pitch ──
            _ExpSection('Speed & Pitch', [
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.link, color: PA.textSecondary),
                title: const Text('Link speed & pitch'),
                subtitle: const Text('Changing speed also shifts pitch',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.linkSpeedPitch,
                onChanged: (v) => st.update(() => st.linkSpeedPitch = v),
              ),
            ]),

            // ── 3. Playback Extras ──
            _ExpSection('Playback Extras', [
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.play_circle_outline, color: PA.textSecondary),
                title: const Text('Play on skip'),
                subtitle: const Text('Next/previous starts playback while paused',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.playOnSkip,
                onChanged: (v) => st.update(() => st.playOnSkip = v),
              ),
              ListTile(
                leading: const Icon(Icons.fast_forward_outlined, color: PA.textSecondary),
                title: const Text('Hold-to-seek step'),
                subtitle: const Text('Jump size while holding next/previous',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                trailing: _dropdown<int>(st.holdSeekSec, {
                  5: '5s', 10: '10s', 15: '15s', 30: '30s',
                }, (v) => st.update(() => st.holdSeekSec = v!)),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.restart_alt, color: PA.textSecondary),
                title: const Text('Restart queue at the end'),
                subtitle: const Text('Return to first track (paused) when queue finishes',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.queueEndRestart,
                onChanged: (v) => st.update(() => st.queueEndRestart = v),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.skip_next, color: PA.textSecondary),
                title: const Text('Previous button replays'),
                subtitle: const Text('Go back to previous instead of replaying',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.previousButtonReplays,
                onChanged: (v) => st.update(() => st.previousButtonReplays = v),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.all_inclusive, color: PA.textSecondary),
                title: const Text('Infinite queue'),
                subtitle: const Text('Continue playing beyond last track',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.infinityQueueNextPrev,
                onChanged: (v) => st.update(() => st.infinityQueueNextPrev = v),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.history, color: PA.textSecondary),
                title: const Text('Collection resume'),
                subtitle: const Text('Remember position per album/playlist',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.collectionResume,
                onChanged: (v) => st.update(() => st.collectionResume = v),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.screen_lock_portrait, color: PA.textSecondary),
                title: const Text('Keep screen awake'),
                subtitle: const Text('Prevent screen from sleeping during playback',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.keepAwake,
                onChanged: (v) => st.update(() => st.keepAwake = v),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.tune, color: PA.textSecondary),
                title: const Text('Per-track audio override'),
                subtitle: const Text('Allow individual tracks to have custom speed/pitch',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.perTrackAudioOverride,
                onChanged: (v) => st.update(() => st.perTrackAudioOverride = v),
              ),
            ]),

            // ── 4. Player UI ──
            _ExpSection('Player UI', [
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.timer_outlined, color: PA.textSecondary),
                title: const Text('Show remaining time'),
                subtitle: const Text('Replace elapsed with remaining on seekbar',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.showRemainingTime,
                onChanged: (v) => st.update(() => st.showRemainingTime = v),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.skip_next, color: PA.textSecondary),
                title: const Text('Show up-next in player'),
                subtitle: const Text('Display next track below the seekbar',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.showUpNext,
                onChanged: (v) => st.update(() => st.showUpNext = v),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.show_chart, color: PA.textSecondary),
                title: const Text('Show waveform'),
                subtitle: const Text('Display audio waveform in player',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.showWaveform,
                onChanged: (v) => st.update(() => st.showWaveform = v),
              ),
              ListTile(
                leading: const Icon(Icons.bar_chart, color: PA.textSecondary),
                title: const Text('Waveform bars'),
                trailing: _dropdown<int>(st.waveformBars, {
                  40: '40', 60: '60', 80: '80', 100: '100', 120: '120',
                }, (v) => st.update(() => st.waveformBars = v!)),
              ),
              ListTile(
                leading: const Icon(Icons.touch_app_outlined, color: PA.textSecondary),
                title: const Text('Artwork tap action'),
                trailing: _dropdown<String>(st.artworkTapAction, {
                  'toggle_lyrics': 'Toggle lyrics',
                  'toggle_controls': 'Toggle controls',
                  'nothing': 'Nothing',
                }, (v) => st.update(() => st.artworkTapAction = v!)),
              ),
              ListTile(
                leading: const Icon(Icons.touch_app, color: PA.textSecondary),
                title: const Text('Artwork long-press action'),
                trailing: _dropdown<String>(st.artworkLongPressAction, {
                  'track_info': 'Track info',
                  'go_to_album': 'Go to album',
                  'go_to_artist': 'Go to artist',
                  'nothing': 'Nothing',
                }, (v) => st.update(() => st.artworkLongPressAction = v!)),
              ),
              ListTile(
                leading: const Icon(Icons.vibration, color: PA.textSecondary),
                title: const Text('Vibration type'),
                trailing: _dropdown<String>(st.vibrationType, {
                  'vibration': 'System vibrate',
                  'haptic': 'Haptic',
                  'none': 'None',
                }, (v) => st.update(() => st.vibrationType = v!)),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.waves, color: PA.textSecondary),
                title: const Text('Media wave haptic'),
                subtitle: const Text('Haptic follows audio rhythm',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.mediaWaveHaptic,
                onChanged: (v) => st.update(() => st.mediaWaveHaptic = v),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.celebration, color: PA.textSecondary),
                title: const Text('Party mode'),
                subtitle: const Text('Animated gradient in miniplayer',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.partyMode,
                onChanged: (v) => st.update(() => st.partyMode = v),
              ),
            ]),

            // ── 5. Library & Indexer ──
            _ExpSection('Library & Indexer', [
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.percent, color: PA.textSecondary),
                title: const Text('Count listens by percent'),
                subtitle: const Text('Threshold as share of track instead of seconds',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.listenPercentMode,
                onChanged: (v) => st.update(() => st.listenPercentMode = v),
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined, color: PA.textSecondary),
                title: const Text('Count a listen after'),
                subtitle: Text(
                    st.listenPercentMode
                        ? '${st.listenPercent}% of the track'
                        : '${st.listenSeconds}s of playback',
                    style: const TextStyle(color: PA.textMuted, fontSize: 12)),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 68, right: 16),
                child: st.listenPercentMode
                    ? _slider(context, 5, 90, st.listenPercent.toDouble(),
                        label: '${st.listenPercent}%',
                        onChanged: (v) => st.update(() => st.listenPercent = v.round()))
                    : _slider(context, 5, 60, st.listenSeconds.toDouble(),
                        label: '${st.listenSeconds}s',
                        onChanged: (v) => st.update(() => st.listenSeconds = v.round())),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.refresh, color: PA.textSecondary),
                title: const Text('Refresh library on startup'),
                subtitle: const Text('Re-scan when app launches',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.refreshOnStartup,
                onChanged: (v) => st.update(() => st.refreshOnStartup = v),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.usb, color: PA.textSecondary),
                title: const Text('Scan on mount'),
                subtitle: const Text('Auto-detect new storage devices',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.scanOnMounted,
                onChanged: (v) => st.update(() => st.scanOnMounted = v),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.image, color: PA.textSecondary),
                title: const Text('Prefer embedded artwork'),
                subtitle: const Text('Use ID3 art before folder images',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.preferEmbeddedArt,
                onChanged: (v) => st.update(() => st.preferEmbeddedArt = v),
              ),
            ]),

            // ── 6. Home Page ──
            _ExpSection('Home Page', [
              ListTile(
                leading: const Icon(Icons.touch_app_outlined, color: PA.textSecondary),
                title: const Text('Tapping a track'),
                trailing: _dropdown<TapMode>(st.tapMode,
                  {for (final m in TapMode.values) m: m.label},
                  (v) { if (v != null) st.update(() => st.tapMode = v); },
                ),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.music_note, color: PA.textSecondary),
                title: const Text('Mixed queue'),
                subtitle: const Text('Allow local and PC tracks in same queue',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.mixedQueueEnabled,
                onChanged: (v) => st.update(() => st.mixedQueueEnabled = v),
              ),
              ListTile(
                leading: const Icon(Icons.grid_view, color: PA.textSecondary),
                title: const Text('Album grid columns'),
                trailing: _dropdown<int>(st.gridColumns, {
                  2: '2 columns', 3: '3 columns',
                }, (v) => st.update(() => st.gridColumns = v!)),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.crop_square, color: PA.textSecondary),
                title: const Text('Force square thumbnails'),
                subtitle: const Text('All album art shows as perfect squares',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.forceSquareThumbnails,
                onChanged: (v) => st.update(() => st.forceSquareThumbnails = v),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.dashboard, color: PA.textSecondary),
                title: const Text('Staggered album grid'),
                subtitle: const Text('Masonry layout for album tiles',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.staggeredAlbumGrid,
                onChanged: (v) => st.update(() => st.staggeredAlbumGrid = v),
              ),
            ]),

            // ── 7. Customization ──
            _ExpSection('Customization', [
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.swap_vert, color: PA.textSecondary),
                title: const Text('Artist before title'),
                subtitle: const Text('Track rows show artist on the main line',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.artistBeforeTitle,
                onChanged: (v) => st.update(() => st.artistBeforeTitle = v),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.format_list_numbered, color: PA.textSecondary),
                title: const Text('Show track numbers'),
                subtitle: const Text('Display track numbers in album views',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.showTrackNumbers,
                onChanged: (v) => st.update(() => st.showTrackNumbers = v),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.calendar_today, color: PA.textSecondary),
                title: const Text('Show album dates'),
                subtitle: const Text('Display year on album cards',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.showAlbumDates,
                onChanged: (v) => st.update(() => st.showAlbumDates = v),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.gradient, color: PA.textSecondary),
                title: const Text('Gradient tiles'),
                subtitle: const Text('Colored gradient overlay on album art',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.gradientTiles,
                onChanged: (v) => st.update(() => st.gradientTiles = v),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.view_list, color: PA.textSecondary),
                title: const Text('Show divider lines'),
                subtitle: const Text('Separators between list items',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.showDividerLines,
                onChanged: (v) => st.update(() => st.showDividerLines = v),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.search, color: PA.textSecondary),
                title: const Text('Always expanded searchbar'),
                subtitle: const Text('Search bar stays fully visible',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.expandedSearchbarAlways,
                onChanged: (v) => st.update(() => st.expandedSearchbarAlways = v),
              ),
              ListTile(
                leading: const Icon(Icons.format_size, color: PA.textSecondary),
                title: const Text('Font scale'),
                trailing: _dropdown<double>(st.fontScale, {
                  0.8: '80%', 0.9: '90%', 1.0: '100%', 1.1: '110%', 1.2: '120%',
                }, (v) => st.update(() => st.fontScale = v!)),
              ),
            ]),

            // ── 8. Tags ──
            _ExpSection('Tag Separators', [
              ListTile(
                leading: const Icon(Icons.people_outline, color: PA.textSecondary),
                title: const Text('Artist separators'),
                subtitle: Text(st.artistSeparators.map((e) => '"$e"').join('  '),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: PA.textMuted, fontSize: 12)),
                onTap: () async {
                  final v = await promptText(context, 'Artist separators (comma-separated)',
                      '; , feat.', initial: st.artistSeparators.join(','));
                  if (v != null) st.update(() => st.artistSeparators = _parseList(v));
                },
              ),
              ListTile(
                leading: const Icon(Icons.piano, color: PA.textSecondary),
                title: const Text('Genre separators'),
                subtitle: Text(st.genreSeparators.map((e) => '"$e"').join('  '),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: PA.textMuted, fontSize: 12)),
                onTap: () async {
                  final v = await promptText(context, 'Genre separators (comma-separated)',
                      '; /', initial: st.genreSeparators.join(','));
                  if (v != null) st.update(() => st.genreSeparators = _parseList(v));
                },
              ),
              ListTile(
                leading: const Icon(Icons.block, color: PA.textSecondary),
                title: const Text('Never split these names'),
                subtitle: Text(st.splitBlacklist.join(', '),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: PA.textMuted, fontSize: 12)),
                onTap: () async {
                  final v = await promptText(context, 'Never-split names (comma-separated)',
                      'AC/DC, Simon & Garfunkel',
                      initial: st.splitBlacklist.join(','));
                  if (v != null) st.update(() => st.splitBlacklist = _parseList(v));
                },
              ),
            ]),

            // ── 9. Track Tile Swipes ──
            _ExpSection('Track Tile Swipes', [
              _SwipePicker(
                label: 'Swipe right',
                value: st.swipeRight,
                onChanged: (a) => st.update(() => st.swipeRight = a),
              ),
              _SwipePicker(
                label: 'Swipe left',
                value: st.swipeLeft,
                onChanged: (a) => st.update(() => st.swipeLeft = a),
              ),
            ]),

            // ── 10. Headphone Actions ──
            _ExpSection('Headphone Actions', [
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.headphones, color: PA.textSecondary),
                title: const Text('Resume on connect'),
                subtitle: const Text('Auto-play when headphones plugged in',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.resumeOnConnect,
                onChanged: (v) => st.update(() => st.resumeOnConnect = v),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.headset_off, color: PA.textSecondary),
                title: const Text('Pause on disconnect'),
                subtitle: const Text('Stop playback when headphones unplugged',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.pauseOnDisconnect,
                onChanged: (v) => st.update(() => st.pauseOnDisconnect = v),
              ),
            ]),

            // ── 11. Appearance ──
            _ExpSection('Appearance', [
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.dark_mode, color: PA.textSecondary),
                title: const Text('OLED theme'),
                subtitle: const Text('Pure black backgrounds (AMOLED battery save)',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.oledTheme,
                onChanged: (v) => st.update(() => st.oledTheme = v),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.animation, color: PA.textSecondary),
                title: const Text('Animations enabled'),
                subtitle: const Text('Turn off to reduce motion',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.animationsEnabled,
                onChanged: (v) => st.update(() => st.animationsEnabled = v),
              ),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.speed, color: PA.textSecondary),
                title: const Text('Performance mode'),
                subtitle: const Text('Reduce visual effects for smoother scroll',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.performanceMode,
                onChanged: (v) => st.update(() => st.performanceMode = v),
              ),
            ]),

            // ── 12. Statistics ──
            _ExpSection('Statistics', [
              ListTile(
                leading: const Icon(Icons.query_stats, color: PA.textSecondary),
                title: const Text('View statistics'),
                subtitle: const Text('Library size and listening totals',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const StatsScreen())),
              ),
            ]),

            // ── 13. Backup & Data ──
            _ExpSection('Backup & Data', [
              const BackupSection(),
              SwitchListTile(
                activeThumbColor: PA.accent,
                secondary: const Icon(Icons.bug_report, color: PA.textSecondary),
                title: const Text('Debug logging'),
                subtitle: const Text('Write detailed logs to disk',
                    style: TextStyle(color: PA.textMuted, fontSize: 12)),
                value: st.debugLogging,
                onChanged: (v) => st.update(() => st.debugLogging = v),
              ),
            ]),

            // ── 14. PC Bridge ──
            _ExpSection('PC Bridge', [
              ListTile(
                leading: const Icon(Icons.computer, color: PA.textSecondary),
                title: const Text('Bridge address'),
                subtitle: Text(s.baseUrl ?? 'Not connected',
                    style: const TextStyle(color: PA.textMuted, fontSize: 12)),
                trailing: TextButton(
                  onPressed: () async {
                    await s.disconnect();
                    if (context.mounted) {
                      Navigator.popUntil(context, (r) => r.isFirst);
                    }
                  },
                  child: const Text('Change', style: TextStyle(color: PA.accent)),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _slider(BuildContext context, double min, double max, double value,
      {String? label, int? partitions, required ValueChanged<double> onChanged}) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: PA.accent,
        inactiveTrackColor: PA.card,
        thumbColor: Colors.white,
      ),
      child: Slider(
        min: min,
        max: max,
        divisions: partitions ?? ((max - min).round()),
        label: label,
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _dropdown<T>(T value, Map<T, String> items, ValueChanged<T?> onChanged) {
    return DropdownButton<T>(
      value: value,
      dropdownColor: PA.surfaceElevated,
      underline: const SizedBox.shrink(),
      style: const TextStyle(fontSize: 13, color: PA.text),
      items: items.entries.map((e) =>
          DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
      onChanged: onChanged,
    );
  }
}

/// Collapsible section header for settings — wraps children
/// in an ExpansionTile to keep long settings lists browsable.
class _ExpSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _ExpSection(this.title, this.children);

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      initiallyExpanded: title == 'Audio & Playback',
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      shape: const Border(),
      title: Text(title,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.bold, color: PA.accent)),
      children: children,
    );
  }
}

List<String> _parseList(String v) => [
      for (final part in v.split(','))
        if (part.trim().isNotEmpty) part.trim()
    ];

class _SwipePicker extends StatelessWidget {
  final String label;
  final SwipeAction value;
  final ValueChanged<SwipeAction> onChanged;
  const _SwipePicker(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
          label.contains('right') ? Icons.swipe_right : Icons.swipe_left,
          color: PA.textSecondary),
      title: Text(label),
      trailing: DropdownButton<SwipeAction>(
        value: value,
        dropdownColor: PA.surfaceElevated,
        underline: const SizedBox.shrink(),
        style: const TextStyle(fontSize: 13, color: PA.text),
        items: [
          for (final a in SwipeAction.values)
            DropdownMenuItem(value: a, child: Text(a.label)),
        ],
        onChanged: (a) {
          if (a != null) onChanged(a);
        },
      ),
    );
  }
}
