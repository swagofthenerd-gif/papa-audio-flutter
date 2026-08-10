import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../history.dart';
import '../models.dart';
import '../theme.dart';

/// Advanced track actions: reset stats, clear history, copy path.
void showTrackAdvanced(BuildContext context, Track track) {
  showModalBottomSheet(
    context: context,
    backgroundColor: PA.surfaceElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _TrackAdvancedSheet(track: track),
  );
}

class _TrackAdvancedSheet extends StatelessWidget {
  final Track track;
  const _TrackAdvancedSheet({required this.track});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final h = app.history;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: PA.textMuted.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Track Actions',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: PA.text)),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.content_copy, color: PA.textSecondary),
              title: const Text('Copy file path'),
              subtitle: Text(track.filePath,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: PA.textMuted, fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt, color: PA.textSecondary),
              title: const Text('Reset play count'),
              subtitle: const Text('Set listen count to zero',
                  style: TextStyle(color: PA.textMuted, fontSize: 11)),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: PA.surfaceElevated,
                    title: const Text('Reset count?', style: TextStyle(color: PA.text)),
                    content: Text('Reset play count for "${track.title}" to zero?',
                        style: const TextStyle(color: PA.textSecondary)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Reset', style: TextStyle(color: PA.error))),
                    ],
                  ),
                );
                if (ok == true) {
                  h.counts.remove(track.key);
                  h.firstListen.remove(track.key);
                  h.lastListen.remove(track.key);
                  h.revision++;
                  h.notifyListeners();
                }
                if (context.mounted) Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep, color: PA.textSecondary),
              title: const Text('Clear listen history'),
              subtitle: const Text('Remove all listen records for this track',
                  style: TextStyle(color: PA.textMuted, fontSize: 11)),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: PA.surfaceElevated,
                    title: const Text('Clear history?', style: TextStyle(color: PA.text)),
                    content: const Text('All listen records for this track will be removed.',
                        style: TextStyle(color: PA.textSecondary)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Clear', style: TextStyle(color: PA.error))),
                    ],
                  ),
                );
                if (ok == true) {
                  await h.clearTrackHistory(track);
                }
                if (context.mounted) Navigator.pop(context);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
