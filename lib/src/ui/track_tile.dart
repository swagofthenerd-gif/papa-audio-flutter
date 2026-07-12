import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../player_service.dart';
import '../theme.dart';
import 'dialogs.dart';
import 'widgets.dart';

/// The one track row used across every list. Namida-style interactions:
/// swipe right → play next, swipe left → add to queue (row snaps back with a
/// snackbar), long-press → context menu, ⋮ → context menu.
class TrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;

  /// Leading override (e.g. rank number in Most Played). Defaults to artwork.
  final Widget? leading;
  final String? subtitleOverride;
  final Widget? trailingExtra;
  final bool showArt;

  /// Disable the built-in swipe gestures when the row lives inside another
  /// Dismissible (playlist / history rows use swipe-to-delete instead).
  final bool swipeActions;

  /// Extra key material for lists that may contain the same track twice.
  final Object? keySalt;

  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.leading,
    this.subtitleOverride,
    this.trailingExtra,
    this.showArt = true,
    this.swipeActions = true,
    this.keySalt,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final ps = s.playerService;
    if (!swipeActions) return _tile(ps);
    return Dismissible(
      key: ValueKey('tt${track.key}#$keySalt'),
      direction: DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.25,
        DismissDirection.endToStart: 0.25,
      },
      confirmDismiss: (dir) async {
        // Perform the action but never actually dismiss — the row snaps back.
        if (dir == DismissDirection.startToEnd) {
          ps.playNext(track);
          _toast(context, 'Playing next: ${track.title}');
        } else {
          ps.addToQueue(track);
          _toast(context, 'Added to queue: ${track.title}');
        }
        return false;
      },
      background: Container(
        color: PA.accent.withValues(alpha: 0.25),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Icon(Icons.playlist_play, color: PA.accent),
      ),
      secondaryBackground: Container(
        color: PA.accent.withValues(alpha: 0.25),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.queue, color: PA.accent),
      ),
      child: _tile(ps),
    );
  }

  Widget _tile(PlayerService ps) {
    return Builder(
      builder: (context) => StreamBuilder<int?>(
        stream: ps.currentIndex,
        builder: (_, _) {
          final isCurrent = ps.currentTrack?.key == track.key;
          return ListTile(
            leading: leading ??
                (showArt
                    ? TrackArt(
                        artUri: track.artUri,
                        artPath: track.artPath,
                        size: 44,
                        px: 120)
                    : null),
            title: Text(track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14,
                    color: isCurrent ? PA.accent : PA.text,
                    fontWeight:
                        isCurrent ? FontWeight.w600 : FontWeight.normal)),
            subtitle: Text(
                subtitleOverride ??
                    '${track.artist}${track.album != null ? ' · ${track.album}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: PA.textSecondary, fontSize: 12)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ?trailingExtra,
                if (track.duration > 0)
                  Text(fmtDuration(track.duration),
                      style:
                          const TextStyle(color: PA.textMuted, fontSize: 11)),
                IconButton(
                  icon: const Icon(Icons.more_vert,
                      color: PA.textMuted, size: 18),
                  onPressed: () => showTrackMenu(context, track),
                ),
              ],
            ),
            onTap: onTap,
            onLongPress: () => showTrackMenu(context, track),
          );
        },
      ),
    );
  }

  static void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg, maxLines: 1, overflow: TextOverflow.ellipsis),
        duration: const Duration(milliseconds: 1400),
        behavior: SnackBarBehavior.floating,
      ));
  }
}
