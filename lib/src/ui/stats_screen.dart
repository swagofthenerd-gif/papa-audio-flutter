import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../history.dart';
import '../theme.dart';

/// Library and listening statistics with interactive charts.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: PA.background,
        title: const Text('Statistics', style: TextStyle(fontSize: 17)),
        bottom: TabBar(
          controller: _tabs,
          labelColor: PA.accent,
          unselectedLabelColor: PA.textSecondary,
          indicatorColor: PA.accent,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Library'),
            Tab(text: 'Listening'),
          ],
        ),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([s.localLibrary, s.history]),
        builder: (context, _) {
          final tracks =
              s.localLibrary.albums.expand((a) => a.tracks).toList();
          final artists = <String>{};
          final genres = <String, int>{};
          var librarySec = 0.0;
          for (final t in tracks) {
            librarySec += t.duration;
            for (final a in s.settings.artistSplitter.split(t.artist)) {
              artists.add(a);
            }
            final g = t.genre?.trim() ?? '';
            if (g.isNotEmpty) {
              for (final single in s.settings.genreSplitter.split(g)) {
                genres[single] = (genres[single] ?? 0) + 1;
              }
            }
          }

          final totalListens =
              s.history.counts.values.fold(0, (a, b) => a + b);
          var listenSec = 0.0;
          for (final (t, n) in s.history.mostPlayed(limit: 1 << 30)) {
            listenSec += t.duration * n;
          }

          return TabBarView(
            controller: _tabs,
            children: [
              _OverviewTab(
                tracks: tracks.length,
                albums: s.localLibrary.albums.length,
                artists: artists.length,
                genres: genres.length,
                librarySec: librarySec,
                totalListens: totalListens,
                listenSec: listenSec,
              ),
              _LibraryTab(
                tracks: tracks,
                genres: genres,
                librarySec: librarySec,
              ),
              _ListeningTab(
                history: s.history,
                totalListens: totalListens,
                listenSec: listenSec,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Overview Tab ─────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  final int tracks, albums, artists, genres;
  final double librarySec;
  final int totalListens;
  final double listenSec;

  const _OverviewTab({
    required this.tracks,
    required this.albums,
    required this.artists,
    required this.genres,
    required this.librarySec,
    required this.totalListens,
    required this.listenSec,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatCard(
          icon: Icons.music_note,
          label: 'Tracks',
          value: '$tracks',
          color: PA.accent,
        ),
        const SizedBox(height: 12),
        _StatCard(
          icon: Icons.album,
          label: 'Albums',
          value: '$albums',
          color: Colors.blue,
        ),
        const SizedBox(height: 12),
        _StatCard(
          icon: Icons.people_outline,
          label: 'Artists',
          value: '$artists',
          color: Colors.orange,
        ),
        const SizedBox(height: 12),
        _StatCard(
          icon: Icons.piano,
          label: 'Genres',
          value: '$genres',
          color: Colors.purple,
        ),
        const SizedBox(height: 12),
        _StatCard(
          icon: Icons.schedule,
          label: 'Library Duration',
          value: _fmtLong(librarySec),
          color: Colors.teal,
        ),
        const SizedBox(height: 12),
        _StatCard(
          icon: Icons.headphones,
          label: 'Total Listens',
          value: '$totalListens',
          color: Colors.pink,
        ),
        const SizedBox(height: 12),
        _StatCard(
          icon: Icons.equalizer,
          label: 'Time Listened',
          value: _fmtLong(listenSec),
          color: Colors.amber,
        ),
      ],
    );
  }

  static String _fmtLong(double seconds) {
    final d = Duration(seconds: seconds.round());
    if (d.inDays > 0) return '${d.inDays} days ${d.inHours % 24} hrs';
    if (d.inHours > 0) return '${d.inHours} hrs ${d.inMinutes % 60} min';
    return '${d.inMinutes} min';
  }
}

// ── Library Tab ──────────────────────────────────────────────

class _LibraryTab extends StatelessWidget {
  final List<dynamic> tracks;
  final Map<String, int> genres;
  final double librarySec;

  const _LibraryTab({
    required this.tracks,
    required this.genres,
    required this.librarySec,
  });

  @override
  Widget build(BuildContext context) {
    final topGenres = genres.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final displayGenres = topGenres.take(8).toList();

    // Duration distribution by genre
    final genreColors = [
      PA.accent,
      Colors.blue,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.amber,
      Colors.red,
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (displayGenres.isNotEmpty) ...[
          Text('Top Genres',
              style: TextStyle(
                  color: PA.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sections: List.generate(displayGenres.length, (i) {
                  final g = displayGenres[i];
                  return PieChartSectionData(
                    value: g.value.toDouble(),
                    title: '${g.key}\n${g.value}',
                    color: genreColors[i % genreColors.length],
                    titleStyle:
                        const TextStyle(fontSize: 11, color: Colors.white),
                    radius: 60,
                  );
                }),
                sectionsSpace: 2,
                centerSpaceRadius: 30,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
        Text('Track Duration Distribution',
            style: TextStyle(
                color: PA.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: _maxBarValue(tracks.length),
              barGroups: _buildDurationBars(),
              titlesData: const FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: _durationBottomTitle,
                  ),
                ),
                leftTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
            ),
          ),
        ),
      ],
    );
  }

  List<BarChartGroupData> _buildDurationBars() {
    final buckets = <int, int>{};
    for (final t in tracks) {
      final dur = (t.duration ?? 0);
      final bucket = dur ~/ 60;
      buckets[bucket] = (buckets[bucket] ?? 0) + 1;
    }
    final maxBucket = buckets.keys.isEmpty ? 10 : buckets.keys.reduce((a, b) => a > b ? a : b);
    return List.generate(maxBucket.clamp(0, 15) + 1, (i) {
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: (buckets[i] ?? 0).toDouble(),
            color: PA.accent,
            width: 12,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      );
    });
  }

  double _maxBarValue(int total) {
    final h = total / 5;
    return h < 1 ? 1 : h;
  }

  static Widget _durationBottomTitle(double value, TitleMeta meta) {
    return Text('${value.toInt()}m',
        style: TextStyle(fontSize: 10, color: PA.textSecondary));
  }
}

// ── Listening Tab ────────────────────────────────────────────

class _ListeningTab extends StatelessWidget {
  final HistoryService history;
  final int totalListens;
  final double listenSec;

  const _ListeningTab({
    required this.history,
    required this.totalListens,
    required this.listenSec,
  });

  @override
  Widget build(BuildContext context) {
    final top = history.mostPlayed(limit: 10);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatCard(
          icon: Icons.headphones,
          label: 'Total Listens',
          value: '$totalListens',
          color: Colors.pink,
        ),
        const SizedBox(height: 12),
        _StatCard(
          icon: Icons.timer,
          label: 'Listening Time',
          value: _OverviewTab._fmtLong(listenSec),
          color: Colors.amber,
        ),
        const SizedBox(height: 12),
        _StatCard(
          icon: Icons.repeat,
          label: 'Average Listens per Track',
          value: totalListens > 0
              ? '${(totalListens / (top.length.clamp(1, 999999))).toStringAsFixed(1)}'
              : '0',
          color: Colors.teal,
        ),
        if (top.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Most Played',
              style: TextStyle(
                  color: PA.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...top.map((entry) {
            final (track, count) = entry;
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: PA.accent.withAlpha(30),
                child: Text('$count',
                    style:
                        TextStyle(color: PA.accent, fontWeight: FontWeight.bold)),
              ),
              title: Text(track.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(track.artist,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            );
          }),
        ],
      ],
    );
  }
}

// ── Shared Widgets ───────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: PA.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: PA.textSecondary, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(value,
                      style: TextStyle(
                          color: PA.text,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
