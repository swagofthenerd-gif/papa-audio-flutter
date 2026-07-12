import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../settings.dart';
import '../theme.dart';
import 'equalizer_screen.dart';

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
