import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../history.dart';
import '../models.dart';
import '../theme.dart';

/// Per-track listen history, day-grouped like Namida.
void showTrackListens(BuildContext context, Track track) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: PA.surfaceElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _TrackListensSheet(track: track),
  );
}

class _TrackListensSheet extends StatelessWidget {
  final Track track;
  const _TrackListensSheet({required this.track});

  @override
  Widget build(BuildContext context) {
    final h = context.read<AppState>().history;
    // Filter history entries for this track (newest first)
    final listens = h.entries
        .where((e) => e.track.key == track.key)
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.25,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scroll) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: PA.textMuted.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Listen History — ${track.title}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: PA.text),
                textAlign: TextAlign.center),
          ),
          if (listens.isEmpty)
            const Expanded(
              child: Center(
                child: Text('No listens recorded yet',
                    style: TextStyle(color: PA.textMuted)),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: listens.length,
                itemBuilder: (context, index) {
                  final e = listens[index];
                  final d = DateTime.fromMillisecondsSinceEpoch(e.at);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 100,
                          child: Text(
                            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
                            style: const TextStyle(color: PA.textSecondary, fontSize: 12),
                          ),
                        ),
                        Text(
                          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(color: PA.textMuted, fontSize: 12),
                        ),
                        const Spacer(),
                        const Icon(Icons.headphones, size: 12, color: PA.accent),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
