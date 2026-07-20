import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../player_service.dart';
import '../settings.dart';
import '../theme.dart';
import 'dialogs.dart';
import 'widgets.dart';

/// The one track row used across every list. Namida-style interactions:
/// configurable swipe actions (defaults: right = play next, left = add to
/// queue; row snaps back with a toast), long-press → menu, ⋮ → menu.
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
    final right = s.settings.swipeRight;
    final left = s.settings.swipeLeft;
    return Dismissible(
      key: ValueKey('tt${track.key}#$keySalt'),
      direction: DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.25,
        DismissDirection.endToStart: 0.25,
      },
      confirmDismiss: (dir) async {
        // Perform the action but never actually dismiss — the row snaps back.
        _perform(context, s,
            dir == DismissDirection.startToEnd ? right : left);
        return false;
      },
      background: Container(
        color: PA.accent.withValues(alpha: 0.25),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: Icon(_icon(right), color: PA.accent),
      ),
      secondaryBackground: Container(
        color: PA.accent.withValues(alpha: 0.25),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(_icon(left), color: PA.accent),
      ),
      child: _tile(ps),
    );
  }

  void _perform(BuildContext context, AppState s, SwipeAction action) {
    switch (action) {
      case SwipeAction.playNext:
        s.playerService.playNext(track);
        _toast(context, 'Playing next: ${track.title}');
      case SwipeAction.addToQueue:
        s.playerService.addToQueue(track);
        _toast(context, 'Added to queue: ${track.title}');
      case SwipeAction.favorite:
        s.playlists.toggleFavorite(track);
        _toast(
            context,
            s.playlists.isFavorite(track)
                ? 'Added to Liked Songs'
                : 'Removed from Liked Songs');
      case SwipeAction.openMenu:
        showTrackMenu(context, track);
    }
  }

  static IconData _icon(SwipeAction a) => switch (a) {
        SwipeAction.playNext => Icons.playlist_play,
        SwipeAction.addToQueue => Icons.queue,
        SwipeAction.favorite => Icons.favorite,
        SwipeAction.openMenu => Icons.more_horiz,
      };

  Widget _tile(PlayerService ps) {
    return Builder(
      builder: (context) {
        final sel = context.read<AppState>().selection;
        return StreamBuilder<int?>(
        stream: ps.currentIndex,
        builder: (_, _) {
          final isCurrent = ps.currentTrack?.key == track.key;
          return AnimatedBuilder(
            animation: sel,
            builder: (context, _) {
          final selected = sel.active && sel.contains(track);
          // Optional Namida-style swap: artist on the main line, title below.
          final artistFirst =
              context.read<AppState>().settings.artistBeforeTitle;
          final titleText = artistFirst ? track.artist : track.title;
          final subtitleText = subtitleOverride ??
              (artistFirst
                  ? '${track.title}${track.album != null ? ' · ${track.album}' : ''}'
                  : '${track.artist}${track.album != null ? ' · ${track.album}' : ''}');
          return ListTile(
            selected: selected,
            selectedTileColor: PA.accent.withValues(alpha: 0.14),
            leading: selected
                ? const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Icons.check_circle, color: PA.accent))
                : leading ??
                    (showArt
                        ? TrackArt(
                            artUri: track.artUri,
                            artPath: track.artPath,
                            size: 44,
                            px: 120)
                        : null),
            title: Text(titleText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14,
                    color: isCurrent ? PA.accent : PA.text,
                    fontWeight:
                        isCurrent ? FontWeight.w600 : FontWeight.normal)),
            subtitle: Text(subtitleText,
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
            onTap: () => sel.active ? sel.toggle(track) : onTap(),
            // Long-press starts (or extends) multi-select, Namida-style; the
            // context menu stays reachable via the ⋮ button. Light haptic tick
            // to confirm the selection engaged.
            onLongPress: () {
              HapticFeedback.selectionClick();
              sel.toggle(track);
            },
          );
            },
          );
        },
        );
      },
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
