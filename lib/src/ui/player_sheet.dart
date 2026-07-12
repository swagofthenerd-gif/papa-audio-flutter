import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../player_service.dart';
import '../theme.dart';
import 'dialogs.dart';
import 'equalizer_screen.dart';
import 'widgets.dart';

/// The persistent player: a mini bar above the nav bar that the user drags up
/// into the full-screen player — one continuous, finger-tracking morph (no
/// route push). Swiping the mini bar left/right changes track. This is the
/// piece that carries the "native player" feel.
class PlayerSheet extends StatefulWidget {
  /// Height of the navigation bar the mini state floats above.
  final double navHeight;
  const PlayerSheet({super.key, required this.navHeight});

  static const miniHeight = 62.0;

  @override
  State<PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends State<PlayerSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  )..addStatusListener((_) => setState(() {}));

  double get t => _c.value;
  bool get expanded => t > 0.5;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // ── Vertical drag: the sheet follows the finger, then springs ──────────────

  void _onVDragUpdate(DragUpdateDetails d, double travel) {
    _c.value -= d.delta.dy / travel;
  }

  void _onVDragEnd(DragEndDetails d, double travel) {
    final fling = -d.velocity.pixelsPerSecond.dy / travel;
    if (fling.abs() > 0.7) {
      _c.fling(velocity: fling);
    } else {
      _c.fling(velocity: t > 0.5 ? 2.2 : -2.2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ps = context.read<AppState>().playerService;
    return StreamBuilder<int?>(
      stream: ps.currentIndex,
      builder: (context, _) {
        final track = ps.currentTrack;
        if (track == null) {
          _c.value = 0;
          return const SizedBox.shrink();
        }
        final size = MediaQuery.sizeOf(context);
        final topInset = MediaQuery.paddingOf(context).top;
        final collapsedTop = size.height - widget.navHeight - PlayerSheet.miniHeight;
        final travel = collapsedTop; // distance between the two states
        final fullSide = (size.width - 48).clamp(0.0, 380.0);

        // Heavy subtrees are built ONCE here (per track/stream event). The
        // per-frame AnimatedBuilder below only repositions and re-fades these
        // exact instances, so Flutter skips rebuilding them (identical widget
        // => element reuse) and the drag morph stays at native frame rate.
        final fullPlayer = _FullPlayer(
          ps: ps,
          track: track,
          topInset: topInset,
          onCollapse: () => _c.fling(velocity: -2.2),
        );
        final miniBar = _MiniBar(ps: ps, track: track);
        final art = IgnorePointer(
          child: SizedBox(
            width: fullSide,
            height: fullSide,
            child: TrackArt(
              artUri: track.artUri,
              artPath: track.artPath,
              size: fullSide,
              radius: 0,
              px: 800,
            ),
          ),
        );
        const miniRect = Rect.fromLTWH(8, 9, 44, 44);
        final fullRect = Rect.fromLTWH(
            (size.width - fullSide) / 2, topInset + 76, fullSide, fullSide);

        return PopScope(
          canPop: !expanded,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _c.fling(velocity: -2.2);
          },
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final top = collapsedTop * (1 - t);
              final miniOpacity = (1 - t * 2.2).clamp(0.0, 1.0);
              final fullOpacity = ((t - 0.55) / 0.45).clamp(0.0, 1.0);
              final artRect =
                  Rect.lerp(miniRect, fullRect, Curves.easeInOut.transform(t))!;
              return Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: top,
                    bottom: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: t < 0.1 ? () => _c.fling(velocity: 2.2) : null,
                      onVerticalDragUpdate: (d) => _onVDragUpdate(d, travel),
                      onVerticalDragEnd: (d) => _onVDragEnd(d, travel),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Color.lerp(PA.surfaceElevated, PA.background, t),
                          borderRadius: BorderRadius.vertical(
                              top: Radius.circular(
                                  12 * (1 - t) + 16 * t * (1 - t))),
                        ),
                        child: Stack(
                          children: [
                            if (fullOpacity > 0)
                              Positioned.fill(
                                child: Opacity(
                                  opacity: fullOpacity,
                                  child: IgnorePointer(
                                    ignoring: fullOpacity < 0.4,
                                    child: fullPlayer,
                                  ),
                                ),
                              ),
                            if (miniOpacity > 0)
                              Positioned(
                                left: 0,
                                right: 0,
                                top: 0,
                                height: PlayerSheet.miniHeight,
                                child: Opacity(
                                  opacity: miniOpacity,
                                  child: IgnorePointer(
                                    ignoring: miniOpacity < 0.4,
                                    child: miniBar,
                                  ),
                                ),
                              ),
                            // Morphing artwork: the SAME decoded image is
                            // scaled between its two rects — no reload/redecode
                            // during the drag.
                            Positioned.fromRect(
                              rect: artRect,
                              child: ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(4 + 6 * t),
                                child: FittedBox(
                                    fit: BoxFit.fill, child: art),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// Mini bar. Owns its horizontal swipe offset so pointer moves only rebuild
/// this small widget, never the whole sheet.
class _MiniBar extends StatefulWidget {
  final PlayerService ps;
  final Track track;
  const _MiniBar({required this.ps, required this.track});

  @override
  State<_MiniBar> createState() => _MiniBarState();
}

class _MiniBarState extends State<_MiniBar> {
  double _hDrag = 0;

  Future<void> _onHDragEnd(DragEndDetails d) async {
    final drag = _hDrag;
    final width = MediaQuery.sizeOf(context).width;
    final v = d.velocity.pixelsPerSecond.dx;
    final commit = drag.abs() > width / 3 || v.abs() > 700;
    if (mounted) setState(() => _hDrag = 0);
    if (commit) {
      final forward = drag < 0 || v < -700;
      forward ? await widget.ps.next() : await widget.ps.previousSmart();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ps = widget.ps;
    final track = widget.track;
    return GestureDetector(
      onHorizontalDragUpdate: (d) => setState(() => _hDrag += d.delta.dx),
      onHorizontalDragEnd: _onHDragEnd,
      child: Column(
        children: [
          StreamBuilder<Duration?>(
            stream: ps.duration,
            builder: (_, durSnap) {
              final total = durSnap.data?.inMilliseconds ?? 0;
              return StreamBuilder<Duration>(
                stream: ps.position,
                builder: (_, posSnap) {
                  final pos = posSnap.data?.inMilliseconds ?? 0;
                  return LinearProgressIndicator(
                    value: total > 0 ? (pos / total).clamp(0.0, 1.0) : 0,
                    minHeight: 2,
                    color: PA.accent,
                    backgroundColor: Colors.transparent,
                  );
                },
              );
            },
          ),
          Expanded(
            child: Row(
              children: [
                const SizedBox(width: 60), // morphing artwork's slot
                Expanded(
                  // Title block slides with the horizontal swipe, hinting the
                  // track change before it commits.
                  child: Transform.translate(
                    offset: Offset(_hDrag * 0.6, 0),
                    child: Opacity(
                      opacity: (1 - (_hDrag.abs() / 260)).clamp(0.25, 1.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                          Text(track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: PA.textSecondary, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ),
                _FavButton(track: track, size: 22),
                StreamBuilder<PlayerState>(
                  stream: ps.playerState,
                  builder: (_, snap) {
                    final playing = snap.data?.playing ?? false;
                    return IconButton(
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                      onPressed: ps.togglePlay,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FullPlayer extends StatelessWidget {
  final PlayerService ps;
  final Track track;
  final double topInset;
  final VoidCallback onCollapse;
  const _FullPlayer(
      {required this.ps,
      required this.track,
      required this.topInset,
      required this.onCollapse});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final artSide = (size.width - 48).clamp(0.0, 380.0);
    return Padding(
      padding: EdgeInsets.only(top: topInset, left: 24, right: 24, bottom: 16),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, size: 30),
                onPressed: onCollapse,
              ),
              const Expanded(
                child: Text('Now Playing',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: PA.textSecondary,
                        letterSpacing: 1.5)),
              ),
              IconButton(
                icon: const Icon(Icons.queue_music),
                onPressed: () => showQueueSheet(context, ps),
              ),
            ],
          ),
          // Swiping the (invisible slot under the) artwork changes track too.
          GestureDetector(
            onHorizontalDragEnd: (d) {
              final v = d.velocity.pixelsPerSecond.dx;
              if (v < -300) ps.next();
              if (v > 300) ps.previousSmart();
            },
            child: SizedBox(height: artSide + 12),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, color: PA.textSecondary)),
                  ],
                ),
              ),
              _FavButton(track: track, size: 26),
            ],
          ),
          const Spacer(),
          SeekBar(ps: ps),
          TransportControls(ps: ps),
          const SizedBox(height: 6),
          // Namida-style utility row: sleep, speed, queue.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ValueListenableBuilder<SleepTimerState?>(
                valueListenable: ps.sleepTimer,
                builder: (_, s, _) => IconButton(
                  icon: Icon(Icons.bedtime_outlined,
                      size: 20, color: s != null ? PA.accent : PA.textMuted),
                  onPressed: () => showSleepTimerSheet(context, ps),
                ),
              ),
              StreamBuilder<double>(
                stream: ps.speedStream,
                builder: (_, snap) {
                  final v = snap.data ?? 1.0;
                  return TextButton(
                    onPressed: () => showSpeedSheet(context, ps),
                    child: Text('${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)}x',
                        style: TextStyle(
                            fontSize: 13,
                            color: v == 1.0 ? PA.textMuted : PA.accent)),
                  );
                },
              ),
              StreamBuilder<bool>(
                stream: ps.equalizer.enabledStream,
                builder: (_, snap) => IconButton(
                  icon: Icon(Icons.equalizer,
                      size: 20,
                      color: (snap.data ?? false) ? PA.accent : PA.textMuted),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const EqualizerScreen())),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.more_horiz, size: 20, color: PA.textMuted),
                onPressed: () => showTrackMenu(context, track),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FavButton extends StatelessWidget {
  final Track track;
  final double size;
  const _FavButton({required this.track, required this.size});
  @override
  Widget build(BuildContext context) {
    final pl = context.read<AppState>().playlists;
    return AnimatedBuilder(
      animation: pl,
      builder: (_, _) {
        final fav = pl.isFavorite(track);
        return IconButton(
          icon: Icon(fav ? Icons.favorite : Icons.favorite_border,
              size: size, color: fav ? PA.accent : PA.textSecondary),
          onPressed: () => pl.toggleFavorite(track),
        );
      },
    );
  }
}

// ── Shared player widgets (also used by dialogs) ─────────────────────────────

class SeekBar extends StatefulWidget {
  final PlayerService ps;
  const SeekBar({super.key, required this.ps});
  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _dragValue; // seconds; non-null while the thumb is being dragged

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration?>(
      stream: widget.ps.duration,
      builder: (_, durSnap) {
        final total = durSnap.data?.inMilliseconds.toDouble() ?? 0;
        return StreamBuilder<Duration>(
          stream: widget.ps.position,
          builder: (_, posSnap) {
            final pos = posSnap.data?.inMilliseconds.toDouble() ?? 0;
            final max = total > 0 ? total : 1.0;
            final value = (_dragValue ?? pos).clamp(0.0, max);
            return Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: PA.accent,
                    inactiveTrackColor: PA.card,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: value,
                    max: max,
                    onChanged: total > 0
                        ? (v) => setState(() => _dragValue = v)
                        : null,
                    onChangeEnd: (v) {
                      widget.ps.seek(Duration(milliseconds: v.round()));
                      setState(() => _dragValue = null);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(fmtDuration(value / 1000),
                          style:
                              const TextStyle(fontSize: 11, color: PA.textMuted)),
                      Text(fmtDuration(total / 1000),
                          style:
                              const TextStyle(fontSize: 11, color: PA.textMuted)),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class TransportControls extends StatelessWidget {
  final PlayerService ps;
  const TransportControls({super.key, required this.ps});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        StreamBuilder<bool>(
          stream: ps.shuffleEnabled,
          builder: (_, snap) {
            final on = snap.data ?? false;
            return IconButton(
              icon:
                  Icon(Icons.shuffle, color: on ? PA.accent : PA.textSecondary),
              onPressed: ps.toggleShuffle,
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.skip_previous, size: 38),
          color: Colors.white,
          onPressed: ps.previousSmart,
        ),
        StreamBuilder<PlayerState>(
          stream: ps.playerState,
          builder: (_, snap) {
            final state = snap.data;
            final playing = state?.playing ?? false;
            final buffering =
                state?.processingState == ProcessingState.loading ||
                    state?.processingState == ProcessingState.buffering;
            return GestureDetector(
              onTap: ps.togglePlay,
              child: Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
                child: buffering
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(
                            strokeWidth: 3, color: Colors.black))
                    : Icon(playing ? Icons.pause : Icons.play_arrow,
                        color: Colors.black, size: 40),
              ),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.skip_next, size: 38),
          color: Colors.white,
          onPressed: ps.next,
        ),
        StreamBuilder<LoopMode>(
          stream: ps.loopMode,
          builder: (_, snap) {
            final mode = snap.data ?? LoopMode.off;
            return IconButton(
              icon: Icon(
                mode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                color: mode == LoopMode.off ? PA.textSecondary : PA.accent,
              ),
              onPressed: ps.cycleRepeat,
            );
          },
        ),
      ],
    );
  }
}

/// Queue sheet: reorder by drag handle, swipe a row away to remove, tap to jump.
void showQueueSheet(BuildContext context, PlayerService ps) {
  showModalBottomSheet(
    context: context,
    backgroundColor: PA.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => _QueueSheet(ps: ps),
  );
}

class _QueueSheet extends StatefulWidget {
  final PlayerService ps;
  const _QueueSheet({required this.ps});
  @override
  State<_QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends State<_QueueSheet> {
  static const _rowHeight = 64.0;
  late final ScrollController _scroll = ScrollController(
    // Open with the playing track a couple of rows from the top.
    initialScrollOffset:
        (((widget.ps.player.currentIndex ?? 0) - 2) * _rowHeight)
            .clamp(0.0, double.infinity),
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ps = widget.ps;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.65,
      child: ValueListenableBuilder<int>(
        valueListenable: ps.queueRevision,
        builder: (_, _, _) => StreamBuilder<int?>(
          stream: ps.currentIndex,
          builder: (_, snap) {
            final current = snap.data ?? -1;
            final queue = ps.queue;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
                  child: Row(
                    children: [
                      Text('Queue · ${queue.length}',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Jump to current',
                        icon: const Icon(Icons.my_location,
                            size: 18, color: PA.textSecondary),
                        onPressed: () => _scroll.animateTo(
                          ((current - 2) * _rowHeight)
                              .clamp(0.0, _scroll.position.maxScrollExtent),
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                      PopupMenuButton<String>(
                        color: PA.surfaceElevated,
                        icon: const Icon(Icons.more_vert,
                            size: 18, color: PA.textSecondary),
                        onSelected: (v) async {
                          final n = switch (v) {
                            'dups' => await ps.removeDuplicates(),
                            'prev' => await ps.removeAllPrevious(),
                            'next' => await ps.removeAllNext(),
                            _ => 0,
                          };
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text('Removed $n tracks'),
                                duration: const Duration(milliseconds: 1200)));
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'dups', child: Text('Remove duplicates')),
                          PopupMenuItem(
                              value: 'prev',
                              child: Text('Remove all previous')),
                          PopupMenuItem(
                              value: 'next', child: Text('Remove all next')),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    scrollController: _scroll,
                    itemExtent: _rowHeight,
                    itemCount: queue.length,
                    onReorderItem: (from, to) => ps.moveInQueue(from, to),
                    itemBuilder: (_, i) {
                      final t = queue[i];
                      final isCurrent = i == current;
                      return Dismissible(
                        key: ValueKey('q$i${t.key}'),
                        direction: isCurrent
                            ? DismissDirection.none
                            : DismissDirection.endToStart,
                        background: Container(
                          color: PA.error,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) async {
                          final removed = await ps.removeFromQueue(i);
                          if (removed != null && context.mounted) {
                            ScaffoldMessenger.of(context)
                              ..clearSnackBars()
                              ..showSnackBar(SnackBar(
                                content: Text('Removed ${removed.title}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                action: SnackBarAction(
                                  label: 'UNDO',
                                  textColor: PA.accent,
                                  onPressed: () => ps.insertAt(i, removed),
                                ),
                              ));
                          }
                        },
                        child: ListTile(
                          leading: TrackArt(
                              artUri: t.artUri,
                              artPath: t.artPath,
                              size: 40,
                              px: 120),
                          title: Text(t.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: isCurrent ? PA.accent : PA.text,
                                  fontWeight: isCurrent
                                      ? FontWeight.w600
                                      : FontWeight.normal)),
                          subtitle: Text(t.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: PA.textSecondary)),
                          trailing: isCurrent
                              ? const Icon(Icons.graphic_eq,
                                  color: PA.accent, size: 18)
                              : ReorderableDragStartListener(
                                  index: i,
                                  child: const Icon(Icons.drag_handle,
                                      color: PA.textMuted, size: 20),
                                ),
                          onTap: () => ps.skipTo(i),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
