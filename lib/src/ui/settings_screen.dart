import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../settings.dart';
import '../theme.dart';
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
            const _Section('Playback'),
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
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: PA.accent,
                    inactiveTrackColor: PA.card,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    min: 100,
                    max: 1000,
                    divisions: 9,
                    label: '${st.fadeMs}ms',
                    value: st.fadeMs.toDouble(),
                    onChanged: (v) => st.update(() => st.fadeMs = v.round()),
                  ),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.compare_arrows, color: PA.textSecondary),
              title: const Text('Transition fade'),
              subtitle: Text(
                  st.transitionFadeSec == 0
                      ? 'Off — tracks change instantly'
                      : 'Fades out/in over ${st.transitionFadeSec}s at track changes',
                  style: const TextStyle(color: PA.textMuted, fontSize: 12)),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 68, right: 16),
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: PA.accent,
                  inactiveTrackColor: PA.card,
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  min: 0,
                  max: 10,
                  divisions: 10,
                  label: st.transitionFadeSec == 0
                      ? 'Off'
                      : '${st.transitionFadeSec}s',
                  value: st.transitionFadeSec.toDouble(),
                  onChanged: (v) =>
                      st.update(() => st.transitionFadeSec = v.round()),
                ),
              ),
            ),
            SwitchListTile(
              activeThumbColor: PA.accent,
              secondary: const Icon(Icons.palette_outlined, color: PA.textSecondary),
              title: const Text('Dynamic player colors'),
              subtitle: const Text('Tint the player with the artwork\'s color',
                  style: TextStyle(color: PA.textMuted, fontSize: 12)),
              value: st.dynamicColors,
              onChanged: (v) => st.update(() => st.dynamicColors = v),
            ),
            SwitchListTile(
              activeThumbColor: PA.accent,
              secondary: const Icon(Icons.fast_forward, color: PA.textSecondary),
              title: const Text('Skip silence'),
              subtitle: const Text('Jump over silent stretches in tracks',
                  style: TextStyle(color: PA.textMuted, fontSize: 12)),
              value: st.skipSilence,
              onChanged: (v) {
                st.update(() => st.skipSilence = v);
                s.playerService.setSkipSilence(v);
              },
            ),
            ListTile(
              leading: const Icon(Icons.touch_app_outlined,
                  color: PA.textSecondary),
              title: const Text('Tapping a track'),
              trailing: DropdownButton<TapMode>(
                value: st.tapMode,
                dropdownColor: PA.surfaceElevated,
                underline: const SizedBox.shrink(),
                style: const TextStyle(fontSize: 12, color: PA.text),
                items: [
                  for (final m in TapMode.values)
                    DropdownMenuItem(value: m, child: Text(m.label)),
                ],
                onChanged: (m) {
                  if (m != null) st.update(() => st.tapMode = m);
                },
              ),
            ),
            SwitchListTile(
              activeThumbColor: PA.accent,
              secondary: const Icon(Icons.restart_alt, color: PA.textSecondary),
              title: const Text('Restart queue at the end'),
              subtitle: const Text(
                  'When the queue finishes, return to the first track (paused)',
                  style: TextStyle(color: PA.textMuted, fontSize: 12)),
              value: st.queueEndRestart,
              onChanged: (v) => st.update(() => st.queueEndRestart = v),
            ),
            SwitchListTile(
              activeThumbColor: PA.accent,
              secondary: const Icon(Icons.link, color: PA.textSecondary),
              title: const Text('Link speed & pitch'),
              subtitle: const Text('Changing speed also shifts pitch',
                  style: TextStyle(color: PA.textMuted, fontSize: 12)),
              value: st.linkSpeedPitch,
              onChanged: (v) => st.update(() => st.linkSpeedPitch = v),
            ),
            const _Section('Library'),
            ListTile(
              leading: const Icon(Icons.timer_outlined, color: PA.textSecondary),
              title: const Text('Count a listen after'),
              subtitle: Text(
                  '${st.listenSeconds}s of playback (or half the track if shorter)',
                  style: const TextStyle(color: PA.textMuted, fontSize: 12)),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 68, right: 16),
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: PA.accent,
                  inactiveTrackColor: PA.card,
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  min: 5,
                  max: 60,
                  divisions: 11,
                  label: '${st.listenSeconds}s',
                  value: st.listenSeconds.toDouble(),
                  onChanged: (v) => st.update(() => st.listenSeconds = v.round()),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.query_stats, color: PA.textSecondary),
              title: const Text('Statistics'),
              subtitle: const Text('Library size and listening totals',
                  style: TextStyle(color: PA.textMuted, fontSize: 12)),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const StatsScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.grid_view, color: PA.textSecondary),
              title: const Text('Album grid columns'),
              trailing: DropdownButton<int>(
                value: st.gridColumns,
                dropdownColor: PA.surfaceElevated,
                underline: const SizedBox.shrink(),
                style: const TextStyle(fontSize: 13, color: PA.text),
                items: const [
                  DropdownMenuItem(value: 2, child: Text('2 columns')),
                  DropdownMenuItem(value: 3, child: Text('3 columns')),
                ],
                onChanged: (v) {
                  if (v != null) st.update(() => st.gridColumns = v);
                },
              ),
            ),
            const _Section('Tags'),
            ListTile(
              leading: const Icon(Icons.people_outline, color: PA.textSecondary),
              title: const Text('Artist separators'),
              subtitle: Text(st.artistSeparators.map((e) => '"$e"').join('  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: PA.textMuted, fontSize: 12)),
              onTap: () async {
                final v = await promptText(
                    context, 'Artist separators (comma-separated)', '; , feat.',
                    initial: st.artistSeparators.join(','));
                if (v != null) {
                  st.update(() => st.artistSeparators = _parseList(v));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.piano, color: PA.textSecondary),
              title: const Text('Genre separators'),
              subtitle: Text(st.genreSeparators.map((e) => '"$e"').join('  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: PA.textMuted, fontSize: 12)),
              onTap: () async {
                final v = await promptText(
                    context, 'Genre separators (comma-separated)', '; /',
                    initial: st.genreSeparators.join(','));
                if (v != null) {
                  st.update(() => st.genreSeparators = _parseList(v));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.block, color: PA.textSecondary),
              title: const Text('Never split these names'),
              subtitle: Text(st.splitBlacklist.join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: PA.textMuted, fontSize: 12)),
              onTap: () async {
                final v = await promptText(context,
                    'Never-split names (comma-separated)', 'AC/DC, Simon & Garfunkel',
                    initial: st.splitBlacklist.join(','));
                if (v != null) {
                  st.update(() => st.splitBlacklist = _parseList(v));
                }
              },
            ),
            const _Section('Track tile swipes'),
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
            const _Section('PC bridge'),
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
                child:
                    const Text('Change', style: TextStyle(color: PA.accent)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<String> _parseList(String v) => [
      for (final part in v.split(','))
        if (part.trim().isNotEmpty) part.trim()
    ];

class _Section extends StatelessWidget {
  final String title;
  const _Section(this.title);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 6),
        child: Text(title,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold, color: PA.accent)),
      );
}

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
