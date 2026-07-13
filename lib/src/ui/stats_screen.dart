import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';

/// Library statistics, Namida-style: collection sizes, total duration, and
/// listening totals derived from history counts.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: PA.background,
        title: const Text('Statistics', style: TextStyle(fontSize: 17)),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([s.localLibrary, s.history]),
        builder: (context, _) {
          final tracks =
              s.localLibrary.albums.expand((a) => a.tracks).toList();
          final artists = <String>{};
          final genres = <String>{};
          var librarySec = 0.0;
          for (final t in tracks) {
            librarySec += t.duration;
            for (final a in s.settings.artistSplitter.split(t.artist)) {
              artists.add(a);
            }
            final g = t.genre?.trim() ?? '';
            if (g.isNotEmpty) genres.addAll(s.settings.genreSplitter.split(g));
          }

          final totalListens =
              s.history.counts.values.fold(0, (a, b) => a + b);
          // Approximate: every counted listen ≈ the track's full duration.
          var listenSec = 0.0;
          for (final (t, n) in s.history.mostPlayed(limit: 1 << 30)) {
            listenSec += t.duration * n;
          }

          final items = <(IconData, String, String)>[
            (Icons.music_note, 'Tracks on this phone', '${tracks.length}'),
            (Icons.album, 'Albums', '${s.localLibrary.albums.length}'),
            (Icons.people_outline, 'Artists', '${artists.length}'),
            (Icons.piano, 'Genres', '${genres.length}'),
            (Icons.schedule, 'Library duration', _fmtLong(librarySec)),
            (Icons.headphones, 'Total listens', '$totalListens'),
            (
              Icons.equalizer,
              'Time listened (approx.)',
              _fmtLong(listenSec)
            ),
          ];

          return ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              for (final (icon, label, value) in items)
                ListTile(
                  leading: Icon(icon, color: PA.textSecondary),
                  title: Text(label),
                  trailing: Text(value,
                      style: const TextStyle(
                          color: PA.accent,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                ),
            ],
          );
        },
      ),
    );
  }

  /// "3 days 4 hrs", "5 hrs 12 min", "42 min" — long-form durations.
  static String _fmtLong(double seconds) {
    final d = Duration(seconds: seconds.round());
    if (d.inDays > 0) return '${d.inDays} days ${d.inHours % 24} hrs';
    if (d.inHours > 0) return '${d.inHours} hrs ${d.inMinutes % 60} min';
    return '${d.inMinutes} min';
  }
}
