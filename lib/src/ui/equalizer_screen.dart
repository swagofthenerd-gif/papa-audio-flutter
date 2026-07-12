import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';

/// System equalizer bands + loudness boost, riding on the player's Android
/// audio pipeline. Band layout comes from the device (usually 5 bands).
class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});
  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  double _boostDb = 0;

  @override
  Widget build(BuildContext context) {
    final ps = context.read<AppState>().playerService;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: PA.background,
        title: const Text('Equalizer', style: TextStyle(fontSize: 17)),
        actions: [
          StreamBuilder<bool>(
            stream: ps.equalizer.enabledStream,
            builder: (_, snap) => Switch(
              value: snap.data ?? false,
              activeThumbColor: PA.accent,
              onChanged: (v) => ps.equalizer.setEnabled(v),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<AndroidEqualizerParameters>(
        future: ps.equalizer.parameters,
        builder: (context, snap) {
          final params = snap.data;
          if (params == null) {
            return const Center(
                child: Text('Equalizer unavailable on this device',
                    style: TextStyle(color: PA.textSecondary)));
          }
          return Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final band in params.bands)
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(
                                child: StreamBuilder<double>(
                                  stream: band.gainStream,
                                  builder: (_, gainSnap) {
                                    final gain = gainSnap.data ?? band.gain;
                                    return RotatedBox(
                                      quarterTurns: -1,
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          activeTrackColor: PA.accent,
                                          inactiveTrackColor: PA.card,
                                          thumbColor: Colors.white,
                                          trackHeight: 3,
                                        ),
                                        child: Slider(
                                          min: params.minDecibels,
                                          max: params.maxDecibels,
                                          value: gain.clamp(params.minDecibels,
                                              params.maxDecibels),
                                          onChanged: band.setGain,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(_hz(band.centerFrequency),
                                  style: const TextStyle(
                                      fontSize: 11, color: PA.textSecondary)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const Divider(color: PA.separator, height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Loudness boost',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        StreamBuilder<bool>(
                          stream: ps.loudness.enabledStream,
                          builder: (_, snap) => Switch(
                            value: snap.data ?? false,
                            activeThumbColor: PA.accent,
                            onChanged: (v) => ps.loudness.setEnabled(v),
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: PA.accent,
                        inactiveTrackColor: PA.card,
                        thumbColor: Colors.white,
                      ),
                      child: Slider(
                        min: 0,
                        max: 10,
                        divisions: 20,
                        label: '+${_boostDb.toStringAsFixed(1)} dB',
                        value: _boostDb,
                        onChanged: (v) {
                          setState(() => _boostDb = v);
                          ps.loudness.setTargetGain(v);
                        },
                      ),
                    ),
                    const Text(
                        'Boost makes quiet recordings louder. High values can distort.',
                        style: TextStyle(fontSize: 11, color: PA.textMuted)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _hz(double hz) =>
      hz >= 1000 ? '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)}k' : '${hz.round()}';
}
