import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../history.dart';
import '../theme.dart';

/// GitHub-style contribution grid showing listen density over the past year.
void showHeatmapView(BuildContext context) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => const HeatmapPage()));
}

class HeatmapPage extends StatelessWidget {
  const HeatmapPage({super.key});

  static const int daysToShow = 365;
  static const int weeksToShow = 53; // ~1 year of weeks

  @override
  Widget build(BuildContext context) {
    final h = context.read<AppState>().history;
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: daysToShow));

    // Build a map of date → listen count
    final Map<String, int> dayCounts = {};
    for (final e in h.entries) {
      if (e.at < start.millisecondsSinceEpoch) break; // newest-first
      final d = DateTime.fromMillisecondsSinceEpoch(e.at);
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      dayCounts.update(key, (n) => n + 1, ifAbsent: () => 1);
    }

    final maxCount = dayCounts.values.fold<int>(0, (a, b) => a > b ? a : b);

    return Scaffold(
      backgroundColor: PA.background,
      appBar: AppBar(
        backgroundColor: PA.background,
        title: const Text('Listening Heatmap', style: TextStyle(fontSize: 17)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Past ${daysToShow} days',
                style: const TextStyle(color: PA.textSecondary, fontSize: 13)),
            const SizedBox(height: 4),
            Text('${h.entries.length} total listens',
                style: const TextStyle(color: PA.textMuted, fontSize: 12)),
            const SizedBox(height: 20),
            Wrap(
              spacing: 3,
              runSpacing: 3,
              children: [
                for (var w = 0; w < weeksToShow; w++)
                  Column(
                    children: [
                      for (var d = 0; d < 7; d++)
                        _dayCell(now.subtract(Duration(days: (weeksToShow - w - 1) * 7 + (6 - d))),
                            dayCounts, maxCount),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _legend('Less', PA.card),
                const SizedBox(width: 4),
                _legend('', PA.accent.withOpacity(0.3)),
                const SizedBox(width: 4),
                _legend('', PA.accent.withOpacity(0.6)),
                const SizedBox(width: 4),
                _legend('', PA.accent),
                const SizedBox(width: 4),
                _legend('More', const Color(0xFF1DB954)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayCell(DateTime day, Map<String, int> counts, int max) {
    final key = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    final count = counts[key] ?? 0;
    Color color;
    if (count == 0) {
      color = PA.card;
    } else if (max == 0) {
      color = PA.accent;
    } else {
      final ratio = count / max;
      if (ratio < 0.25) {
        color = PA.accent.withOpacity(0.25);
      } else if (ratio < 0.5) {
        color = PA.accent.withOpacity(0.5);
      } else if (ratio < 0.75) {
        color = PA.accent.withOpacity(0.75);
      } else {
        color = PA.accent;
      }
    }

    return Tooltip(
      message: '$key — $count listens',
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _legend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(label, style: const TextStyle(color: PA.textMuted, fontSize: 10)),
          ),
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}
