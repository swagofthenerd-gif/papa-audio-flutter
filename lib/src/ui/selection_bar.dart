import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';
import 'dialogs.dart';

/// Bulk-action bar that appears while a multi-selection is active. Screens
/// hosting track lists mount it once (bottom of their Scaffold/stack); it
/// renders nothing when the selection is empty.
class SelectionBar extends StatelessWidget {
  const SelectionBar({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final sel = s.selection;
    return AnimatedBuilder(
      animation: sel,
      builder: (context, _) {
        if (!sel.active) return const SizedBox.shrink();
        return Material(
          color: PA.surfaceElevated,
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 54,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: sel.clear,
                  ),
                  Text('${sel.count}',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: PA.accent)),
                  const Spacer(),
                  _Action(
                    icon: Icons.play_arrow,
                    label: 'Play',
                    onTap: () {
                      final t = sel.tracks;
                      sel.clear();
                      s.playerService.playQueue(t, 0);
                    },
                  ),
                  _Action(
                    icon: Icons.playlist_play,
                    label: 'Next',
                    onTap: () {
                      final t = sel.tracks;
                      sel.clear();
                      _toast(context, 'Playing ${t.length} next');
                      () async {
                        for (final x in t) {
                          await s.playerService.playNext(x); // chains in order
                        }
                      }();
                    },
                  ),
                  _Action(
                    icon: Icons.queue,
                    label: 'Queue',
                    onTap: () {
                      final t = sel.tracks;
                      sel.clear();
                      _toast(context, 'Queued ${t.length} tracks');
                      () async {
                        for (final x in t) {
                          await s.playerService.addToQueue(x);
                        }
                      }();
                    },
                  ),
                  _Action(
                    icon: Icons.playlist_add,
                    label: 'Playlist',
                    onTap: () {
                      final t = sel.tracks;
                      sel.clear();
                      showAddToPlaylistSheet(context, t);
                    },
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static void _toast(BuildContext context, String msg) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
          content: Text(msg),
          duration: const Duration(milliseconds: 1400),
          behavior: SnackBarBehavior.floating));
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Action({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: PA.accent),
            Text(label,
                style: const TextStyle(fontSize: 10, color: PA.textSecondary)),
          ],
        ),
      ),
    );
  }
}
