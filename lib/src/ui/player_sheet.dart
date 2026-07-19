import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../main.dart' show Shell;
import '../app_state.dart';
import '../lyrics.dart';
import '../models.dart';
import '../player_service.dart';
import '../theme.dart';
import '../waveform.dart';
import 'dialogs.dart';
import 'equalizer_screen.dart';
import 'music_hub.dart';
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

  /// Registered by the live sheet state. Returns true when it consumed a
  /// back press (closed the queue panel or collapsed the expanded player).
  /// The Shell's single PopScope calls this first — the sheet must NOT have
  /// its own PopScope, or one back press would trigger both handlers.
  static bool Function()? backHandler;

  @override
  State<PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends State<PlayerSheet>
    with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  )..addStatusListener((_) => setState(() {}));

  /// In-player queue panel position (0 hidden → 1 open). Dragging up while
  /// expanded pulls it in, Namida-style.
  late final AnimationController _q = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  bool _qDragging = false;

  double get t => _c.value;
  bool get expanded => t > 0.5;

  /// Critically-damped spring settle that carries the finger's release
  /// velocity — this is what makes flings feel continuous instead of snapping
  /// to a canned tween.
  static void _spring(AnimationController c, double target, double velocity) {
    c.animateWith(SpringSimulation(
      SpringDescription.withDampingRatio(mass: 1, stiffness: 420, ratio: 1.0),
      c.value,
      target,
      velocity,
    ));
  }

  /// Lyrics view replaces the artwork while on (toggled by double-tap or the
  /// lyrics button). Lives here so the morphing artwork can hide with it.
  final ValueNotifier<bool> lyricsOn = ValueNotifier(false);

  /// Video overlay on (YouTube tracks only). Playing a muxed stream through the
  /// video engine while just_audio is paused — see YtVideoController.
  final ValueNotifier<bool> videoOn = ValueNotifier(false);

  Color? _artColor; // dominant artwork color for the expanded background
  String? _artColorKey;

  // Animated color cross-fade on track change: _artColorShown chases
  // _artColor so the background glides between palettes instead of snapping.
  Color? _artColorShown;
  late final AnimationController _colorC = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 450));
  ColorTween? _colorTween;

  void _animateArtColor(Color? to) {
    _colorTween = ColorTween(begin: _artColorShown, end: to);
    _colorC
      ..reset()
      ..forward();
  }

  /// Toggle the video overlay for the current YouTube track. Pauses audio and
  /// hands off to the video engine; toggling off resumes audio at the video's
  /// position.
  Future<void> _toggleVideo(String videoId) async {
    final s = context.read<AppState>();
    if (videoOn.value) {
      videoOn.value = false;
      s.playerService.videoActive = false;
      final at = await s.ytVideo.close();
      await s.playerService.resumeFromVideo(at);
    } else {
      videoOn.value = true;
      final at = await s.playerService.suspendForVideo();
      // While video owns playback, route the transport play/pause to it.
      s.playerService
        ..videoActive = true
        ..onVideoPlayPause = () {
          final c = s.ytVideo.controller;
          if (c == null) return;
          c.value.isPlaying ? c.pause() : c.play();
        };
      await s.ytVideo.open(videoId, fromSec: at);
      if (s.ytVideo.error != null && mounted) {
        // Couldn't resolve a video stream — fall back to audio.
        videoOn.value = false;
        s.playerService.videoActive = false;
        await s.playerService.resumeFromVideo(at);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Video unavailable for this track')));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    PlayerSheet.backHandler = () {
      if (_q.value > 0.05) {
        _spring(_q, 0, -4); // back closes the queue panel first
        return true;
      }
      if (expanded) {
        _spring(_c, 0, -3);
        return true;
      }
      return false;
    };
  }

  @override
  void dispose() {
    if (PlayerSheet.backHandler != null) PlayerSheet.backHandler = null;
    lyricsOn.dispose();
    videoOn.dispose();
    _c.dispose();
    _q.dispose();
    _colorC.dispose();
    super.dispose();
  }

  void _updateArtColor(BuildContext context, Track track) {
    if (_artColorKey == track.key) return;
    // Track changed (e.g. user skipped) — tear down any video overlay so it
    // can't play the wrong clip, and resume audio for the new track.
    if (videoOn.value) {
      videoOn.value = false;
      final s = context.read<AppState>();
      s.playerService.videoActive = false;
      s.ytVideo.close();
      s.playerService.resumeFromVideo(0);
    }
    _artColorKey = track.key;
    final s = context.read<AppState>();
    if (!s.settings.dynamicColors) {
      _artColor = null;
      _animateArtColor(null);
      return;
    }
    s.artColors.forTrack(track).then((c) {
      if (mounted && _artColorKey == track.key) {
        setState(() {
          _artColor = c;
          _animateArtColor(c);
        });
      }
    });
  }

  // ── Vertical drag: the sheet follows the finger, then springs ──────────────
  // While fully expanded, an upward drag (or any drag with the queue panel
  // already out) is routed to the queue panel instead of the sheet.

  void _onVDragUpdate(DragUpdateDetails d, double travel, double qTravel) {
    if (_qDragging || _q.value > 0.001 || (t > 0.999 && d.delta.dy < 0)) {
      _qDragging = true;
      _q.value = (_q.value - d.delta.dy / qTravel).clamp(0.0, 1.0);
      return;
    }
    _c.value -= d.delta.dy / travel;
  }

  void _onVDragEnd(DragEndDetails d, double travel, double qTravel) {
    if (_qDragging) {
      _qDragging = false;
      final fling = -d.velocity.pixelsPerSecond.dy / qTravel;
      final target =
          fling.abs() > 0.7 ? (fling > 0 ? 1.0 : 0.0) : (_q.value > 0.5 ? 1.0 : 0.0);
      HapticFeedback.selectionClick();
      _spring(_q, target, fling);
      return;
    }
    final fling = -d.velocity.pixelsPerSecond.dy / travel;
    HapticFeedback.selectionClick(); // snap tick, Namida-style
    if (fling.abs() > 0.7) {
      _spring(_c, fling > 0 ? 1.0 : 0.0, fling);
    } else {
      _spring(_c, t > 0.5 ? 1.0 : 0.0, fling);
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
        // Artwork side: capped by width AND by what the column below it needs
        // (header/title/seek/controls/utility ≈ 420px) so the full player
        // NEVER overflows on short screens — the art shrinks instead.
        final fullSide = math.min(
          (size.width - 48).clamp(0.0, 380.0),
          (size.height - topInset - 420).clamp(140.0, 380.0),
        );

        // Heavy subtrees are built ONCE here (per track/stream event). The
        // per-frame AnimatedBuilder below only repositions and re-fades these
        // exact instances, so Flutter skips rebuilding them (identical widget
        // => element reuse) and the drag morph stays at native frame rate.
        _updateArtColor(context, track);
        final fullPlayer = _FullPlayer(
          ps: ps,
          track: track,
          topInset: topInset,
          artSide: fullSide,
          lyricsOn: lyricsOn,
          videoOn: videoOn,
          onToggleVideo: _toggleVideo,
          onCollapse: () => _spring(_c, 0, -3),
          onQueue: () => _spring(_q, 1, 4),
        );
        final miniBar = _MiniBar(ps: ps, track: track);
        // Swipeable artwork carousel — mounted only while fully expanded so
        // the morphing single-art keeps owning every in-between frame.
        final carousel = _ArtCarousel(
          ps: ps,
          track: track,
          side: fullSide,
          lyricsOn: lyricsOn,
          glow: _artColor,
        );
        // Pseudo-blur backdrop: a tiny decode stretched full-screen; bilinear
        // upscaling reads as a blur at near-zero cost (no ImageFiltered).
        final bgArt = IgnorePointer(
          child: RepaintBoundary(
            child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: 60,
              height: 60,
              child: TrackArt(
                artUri: track.artUri,
                artPath: track.artPath,
                size: 60,
                radius: 0,
                px: 32,
              ),
            ),
          ),
          ),
        );
        final qHeight = size.height * 0.68;
        // Built ONCE per stream event — the per-frame builder only positions
        // it. Rebuilding a ReorderableListView every drag frame is jank.
        final queuePanel = Material(
          color: PA.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(16)),
          clipBehavior: Clip.antiAlias,
          elevation: 8,
          child: Column(
            children: [
              // Grab handle — also a tap target to close.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _spring(_q, 0, -4),
                child: Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 8, bottom: 2),
                    decoration: BoxDecoration(
                      color: PA.textMuted,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              Expanded(child: QueuePanel(ps: ps)),
            ],
          ),
        );
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
        // Lands 8px below the header row; the _FullPlayer placeholder brackets
        // this rect exactly so artwork never overlaps title or controls.
        final fullRect = Rect.fromLTWH(
            (size.width - fullSide) / 2, topInset + 56, fullSide, fullSide);

        return AnimatedBuilder(
          animation: Listenable.merge([_c, _q, _colorC]),
          builder: (context, _) {
              _artColorShown = _colorTween?.evaluate(_colorC) ?? _artColor;
              final top = collapsedTop * (1 - t);
              // Collapsed, the sheet is ONLY the mini strip (the nav bar stays
              // visible and tappable below it); expanded it fills the screen.
              final bottom = widget.navHeight * (1 - t);
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
                    bottom: bottom,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: t < 0.1 ? () => _spring(_c, 1, 3) : null,
                      onVerticalDragUpdate: (d) =>
                          _onVDragUpdate(d, travel, qHeight),
                      onVerticalDragEnd: (d) =>
                          _onVDragEnd(d, travel, qHeight),
                      child: Container(
                        decoration: BoxDecoration(
                          // Expanded background: top-weighted gradient from
                          // the artwork's dominant color fading into the app
                          // background — Namida/Spotify style. The color
                          // itself cross-fades on track change (_colorC).
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.0, 0.55, 1.0],
                            colors: [
                              Color.lerp(
                                  PA.surfaceElevated,
                                  _artColorShown != null
                                      ? Color.lerp(PA.background,
                                          _artColorShown, 0.55)!
                                      : PA.background,
                                  t)!,
                              Color.lerp(
                                  PA.surfaceElevated,
                                  _artColorShown != null
                                      ? Color.lerp(PA.background,
                                          _artColorShown, 0.22)!
                                      : PA.background,
                                  t)!,
                              Color.lerp(
                                  PA.surfaceElevated, PA.background, t)!,
                            ],
                          ),
                          borderRadius: BorderRadius.vertical(
                              top: Radius.circular(
                                  12 * (1 - t) + 16 * t * (1 - t))),
                        ),
                        child: Stack(
                          children: [
                            // Blurry artwork backdrop under everything (only
                            // near-expanded, faded in over the last 10%).
                            if (t > 0.9)
                              Positioned.fill(
                                child: Opacity(
                                  opacity:
                                      0.28 * ((t - 0.9) / 0.1).clamp(0.0, 1.0),
                                  child: bgArt,
                                ),
                              ),
                            if (fullOpacity > 0)
                              Positioned.fill(
                                child: Opacity(
                                  opacity: fullOpacity,
                                  child: IgnorePointer(
                                    ignoring: fullOpacity < 0.4,
                                    // Parallax: content settles up into place
                                    // slightly behind the sheet itself.
                                    child: Transform.translate(
                                      offset: Offset(0, (1 - t) * 40),
                                      child: fullPlayer,
                                    ),
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
                            // during the drag. Hidden while lyrics are showing
                            // in the expanded player.
                            Positioned.fromRect(
                              rect: artRect,
                              child: ValueListenableBuilder<bool>(
                                valueListenable: lyricsOn,
                                builder: (_, lyr, child) {
                                  if (lyr && t > 0.5) {
                                    return const SizedBox.shrink();
                                  }
                                  // Fully expanded: the swipeable carousel
                                  // takes over the rect. Any collapse drag
                                  // (t < 1) hands back to the morphing art.
                                  if (t >= 0.999) return carousel;
                                  return child!;
                                },
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius:
                                        BorderRadius.circular(4 + 6 * t),
                                    boxShadow: [
                                      // Soft colored glow under the art,
                                      // grows in with expansion.
                                      if (t > 0.3 && _artColorShown != null)
                                        BoxShadow(
                                          color: _artColorShown!
                                              .withValues(alpha: 0.45 * t),
                                          blurRadius: 32 * t,
                                          spreadRadius: 2 * t,
                                          offset: Offset(0, 10 * t),
                                        ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(4 + 6 * t),
                                    child: FittedBox(
                                        fit: BoxFit.fill, child: art),
                                  ),
                                ),
                              ),
                            ),
                            // Video overlay (YouTube tracks): occupies the art
                            // rect only when expanded and the video is playing.
                            if (t > 0.5)
                              Positioned.fromRect(
                                rect: artRect,
                                child: ValueListenableBuilder<bool>(
                                  valueListenable: videoOn,
                                  builder: (_, on, _) => on
                                      ? _VideoOverlay(radius: 4 + 6 * t)
                                      : const SizedBox.shrink(),
                                ),
                              ),
                            // In-player queue panel: slides up from the bottom
                            // edge, pulled by the drag router above.
                            if (t > 0.95 && _q.value > 0.001)
                              Positioned(
                                left: 0,
                                right: 0,
                                height: qHeight,
                                bottom: qHeight * (_q.value - 1),
                                child: queuePanel,
                              ),
                          ],
                        ),
                      ),
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
      HapticFeedback.selectionClick();
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
          // RepaintBoundary: the strip updates ~5x/s for hours — it must
          // repaint alone, not drag the artwork/text row with it.
          RepaintBoundary(
            child: StreamBuilder<Duration?>(
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
                      icon: _AnimatedPlayPause(
                          playing: playing, size: 24, color: PA.text),
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

/// Play/pause glyph that morphs between the two icons instead of hard-swapping.
class _AnimatedPlayPause extends StatefulWidget {
  final bool playing;
  final double size;
  final Color color;
  const _AnimatedPlayPause(
      {required this.playing, required this.size, required this.color});
  @override
  State<_AnimatedPlayPause> createState() => _AnimatedPlayPauseState();
}

class _AnimatedPlayPauseState extends State<_AnimatedPlayPause>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: widget.playing ? 1 : 0);

  @override
  void didUpdateWidget(_AnimatedPlayPause old) {
    super.didUpdateWidget(old);
    if (widget.playing != old.playing) {
      widget.playing ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedIcon(
        icon: AnimatedIcons.play_pause,
        progress: _c,
        size: widget.size,
        color: widget.color,
      );
}

/// Swipeable artwork carousel for the expanded player: the current art plus
/// its audible neighbors (shuffle/loop-aware via PlayerService), dragged with
/// the finger and spring-settled. Committing a swipe changes the track; the
/// resulting index-change rebuild recenters the carousel on the new current.
class _ArtCarousel extends StatefulWidget {
  final PlayerService ps;
  final Track track;
  final double side;
  final ValueNotifier<bool> lyricsOn;
  final Color? glow; // dominant art color for the soft shadow
  const _ArtCarousel(
      {required this.ps,
      required this.track,
      required this.side,
      required this.lyricsOn,
      this.glow});

  @override
  State<_ArtCarousel> createState() => _ArtCarouselState();
}

class _ArtCarouselState extends State<_ArtCarousel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _settle =
      AnimationController.unbounded(vsync: this)
        ..addListener(() => setState(() => _drag = _settle.value));
  double _drag = 0;
  bool _switching = false; // swipe committed, waiting for the track change

  // Art subtrees cached by track key: drag frames then reuse the exact same
  // widget instances, so Flutter skips rebuilding the image subtree entirely.
  final Map<String, Widget> _artCache = {};

  static const _gap = 24.0;

  @override
  void didUpdateWidget(covariant _ArtCarousel old) {
    super.didUpdateWidget(old);
    if (old.track.key != widget.track.key) {
      // Bounded cache: reset when it grows past the tracks near current.
      if (_artCache.length > 8) _artCache.clear();
      // New current track — it was the card the swipe centered, so snapping
      // the offset back to 0 under the new build is seamless.
      _settle.stop();
      _drag = 0;
      _switching = false;
    }
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _to(double target, double velocity) {
    _settle.value = _drag;
    _settle.animateWith(SpringSimulation(
      SpringDescription.withDampingRatio(mass: 1, stiffness: 500, ratio: 1.0),
      _drag,
      target,
      velocity,
    ));
  }

  Future<void> _end(DragEndDetails d) async {
    if (_switching) return;
    final v = d.velocity.pixelsPerSecond.dx;
    final side = widget.side;
    final commit = _drag.abs() > side / 3 || v.abs() > 700;
    final forward = _drag < 0 || v < -700;
    final neighbor = forward
        ? widget.ps.effectiveNextTrack
        : widget.ps.effectivePreviousTrack;
    if (!commit || neighbor == null) {
      _to(0, v);
      return;
    }
    _switching = true;
    HapticFeedback.selectionClick();
    _to(forward ? -(side + _gap) : (side + _gap), v);
    forward ? await widget.ps.next() : await widget.ps.previous();
    // The index-change rebuild recenters via didUpdateWidget. If it never
    // comes (e.g. loop-one keeps the same index), snap back.
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted && _switching) {
        _switching = false;
        _to(0, 0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final side = widget.side;
    final prev = widget.ps.effectivePreviousTrack;
    final next = widget.ps.effectiveNextTrack;

    Widget slot(Track? tr, double off) {
      final x = off + _drag;
      final centered = (1 - (x.abs() / (side + _gap))).clamp(0.0, 1.0);
      // Cards shrink slightly as they leave center — cheap depth cue.
      final scale = 1 - 0.08 * (1 - centered);
      return Positioned(
        left: x,
        top: 0,
        width: side,
        height: side,
        child: Transform.scale(
          scale: scale,
          child: tr == null
              ? const SizedBox.shrink()
              : DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      if (widget.glow != null && centered > 0.2)
                        BoxShadow(
                          color: widget.glow!
                              .withValues(alpha: 0.45 * centered),
                          blurRadius: 32,
                          spreadRadius: 2,
                          offset: const Offset(0, 10),
                        ),
                    ],
                  ),
                  child: _artCache.putIfAbsent(
                    tr.key,
                    () => RepaintBoundary(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: TrackArt(
                          artUri: tr.artUri,
                          artPath: tr.artPath,
                          size: side,
                          radius: 0,
                          px: 800,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: () => widget.lyricsOn.value = !widget.lyricsOn.value,
      onHorizontalDragUpdate: (d) {
        if (!_switching) setState(() => _drag += d.delta.dx);
      },
      onHorizontalDragEnd: _end,
      child: SizedBox(
        width: side,
        height: side,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            slot(prev, -(side + _gap)),
            slot(next, side + _gap),
            slot(widget.track, 0), // current on top
          ],
        ),
      ),
    );
  }
}

/// Single-line text that auto-scrolls when it overflows, with a hold at each
/// end. Renders a plain Text when it fits — zero cost for short titles.
class _Marquee extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _Marquee({required this.text, required this.style});
  @override
  State<_Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<_Marquee>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(seconds: 7));

  // Measured text width, cached by (text, style) — TextPainter.layout is not
  // free and build runs per frame while the sheet animates.
  double? _textW;
  String? _measuredText;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, cons) {
      if (_measuredText != widget.text) {
        _measuredText = widget.text;
        _textW = (TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout())
            .width;
      }
      final overflow = _textW! - cons.maxWidth;
      if (overflow <= 0) {
        // The ticker must be dead when nothing scrolls — a repeating
        // controller keeps the whole app pumping frames forever.
        if (_c.isAnimating) _c.stop();
        return Text(widget.text,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: widget.style);
      }
      if (!_c.isAnimating) _c.repeat(reverse: true);
      return RepaintBoundary(
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) {
              // Hold 25% at each end, scroll across the middle 50%.
              final p = ((_c.value - 0.25) / 0.5).clamp(0.0, 1.0);
              return Transform.translate(
                offset: Offset(-overflow * p, 0),
                child: SizedBox(
                  width: _textW,
                  child: Text(widget.text,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: widget.style),
                ),
              );
            },
          ),
        ),
      );
    });
  }
}

/// Shrinks its child slightly while pressed. Listener-based so it never
/// competes with the child's own tap/long-press handlers.
class _PressScale extends StatefulWidget {
  final Widget child;
  const _PressScale({required this.child});
  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// The YouTube video overlay: fills the artwork rect while active. Its own
/// audio comes from the muxed stream, so just_audio stays paused meanwhile.
class _VideoOverlay extends StatelessWidget {
  final double radius;
  const _VideoOverlay({required this.radius});
  @override
  Widget build(BuildContext context) {
    final vid = context.read<AppState>().ytVideo;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: AnimatedBuilder(
          animation: vid,
          builder: (_, _) {
            if (vid.loading) {
              return const CircularProgressIndicator(color: PA.accent);
            }
            final c = vid.controller;
            if (c == null || !c.value.isInitialized) {
              return const Icon(Icons.ondemand_video,
                  color: PA.textMuted, size: 40);
            }
            return FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: c.value.size.width,
                height: c.value.size.height,
                child: VideoPlayer(c),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FullPlayer extends StatelessWidget {
  final PlayerService ps;
  final Track track;
  final double topInset;
  final double artSide; // must match the sheet's morph target rect
  final ValueNotifier<bool> lyricsOn;
  final ValueNotifier<bool> videoOn;
  final Future<void> Function(String videoId) onToggleVideo;
  final VoidCallback onCollapse;
  final VoidCallback onQueue;
  const _FullPlayer(
      {required this.ps,
      required this.track,
      required this.topInset,
      required this.artSide,
      required this.lyricsOn,
      required this.videoOn,
      required this.onToggleVideo,
      required this.onCollapse,
      required this.onQueue});

  @override
  Widget build(BuildContext context) {
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
                onPressed: onQueue,
              ),
            ],
          ),
          // The artwork slot: swipe changes track, double-tap toggles lyrics.
          // While lyrics are on, the morphing art hides and this panel shows
          // the synced lines in the same rect.
          GestureDetector(
            onDoubleTap: () => lyricsOn.value = !lyricsOn.value,
            onHorizontalDragEnd: (d) {
              final v = d.velocity.pixelsPerSecond.dx;
              if (v < -300) ps.next();
              if (v > 300) ps.previousSmart();
            },
            child: ValueListenableBuilder<bool>(
              valueListenable: lyricsOn,
              builder: (_, lyr, _) => SizedBox(
                height: artSide + 16,
                child: lyr
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: _LyricsPanel(ps: ps, track: track),
                      )
                    : null,
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Spotify-style: title opens the album, artist opens the
                    // artist hub (YouTube → PC → on-phone, labeled sections).
                    // Collapse the sheet first — it's an overlay above the
                    // navigator, so a pushed route would otherwise appear
                    // *behind* the still-expanded player.
                    GestureDetector(
                      onTap: () {
                        onCollapse();
                        openAlbum(context, context.read<AppState>(), track);
                      },
                      child: _Marquee(
                          text: track.title,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () {
                        onCollapse();
                        openArtist(context, context.read<AppState>(), track);
                      },
                      child: _Marquee(
                          text: track.artist,
                          style: const TextStyle(
                              fontSize: 15, color: PA.textSecondary)),
                    ),
                  ],
                ),
              ),
              _FavButton(track: track, size: 26),
            ],
          ),
          const Spacer(),
          SeekBar(ps: ps, track: track),
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
              ValueListenableBuilder<bool>(
                valueListenable: lyricsOn,
                builder: (_, lyr, _) => IconButton(
                  tooltip: 'Lyrics',
                  icon: Icon(Icons.lyrics_outlined,
                      size: 20, color: lyr ? PA.accent : PA.textMuted),
                  onPressed: () => lyricsOn.value = !lyr,
                ),
              ),
              // Video toggle — YouTube tracks only.
              if (track.id.startsWith('yt:'))
                ValueListenableBuilder<bool>(
                  valueListenable: videoOn,
                  builder: (_, on, _) => IconButton(
                    tooltip: on ? 'Hide video' : 'Show video',
                    icon: Icon(on ? Icons.music_note : Icons.ondemand_video_outlined,
                        size: 20, color: on ? PA.accent : PA.textMuted),
                    onPressed: () => onToggleVideo(track.id.substring(3)),
                  ),
                ),
              StreamBuilder<bool>(
                stream: ps.equalizer.enabledStream,
                builder: (_, snap) => IconButton(
                  icon: Icon(Icons.equalizer,
                      size: 20,
                      color: (snap.data ?? false) ? PA.accent : PA.textMuted),
                  onPressed: () {
                    onCollapse();
                    Navigator.push(
                        Shell.contentContext(context),
                        MaterialPageRoute(
                            builder: (_) => const EqualizerScreen()));
                  },
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

/// Synced-lyrics karaoke view: previous/current/next lines with the active one
/// highlighted, driven by the position stream over a binary-searched index.
/// Falls back to scrollable plain text when only unsynced lyrics exist.
class _LyricsPanel extends StatelessWidget {
  final PlayerService ps;
  final Track track;
  const _LyricsPanel({required this.ps, required this.track});

  @override
  Widget build(BuildContext context) {
    final svc = context.read<AppState>().lyrics;
    if (svc == null) return const SizedBox.shrink();
    return FutureBuilder<Lyrics?>(
      future: svc.forTrack(track),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
              child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: PA.accent)));
        }
        final lyrics = snap.data;
        if (lyrics == null || lyrics.isEmpty) {
          return const Center(
              child: Text('No lyrics found',
                  style: TextStyle(color: PA.textSecondary)));
        }
        if (!lyrics.hasSynced) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(lyrics.plain,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: PA.textSecondary, fontSize: 15, height: 1.6)),
          );
        }
        return StreamBuilder<Duration>(
          stream: ps.position,
          builder: (_, posSnap) {
            final idx =
                lrcLineIndexAt(lyrics.synced, posSnap.data ?? Duration.zero);
            String lineAt(int i) =>
                (i >= 0 && i < lyrics.synced.length) ? lyrics.synced[i].text : '';
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final off in [-2, -1])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(lineAt(idx + off),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: PA.textMuted, fontSize: 15)),
                  ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: Text(idx >= 0 ? lineAt(idx) : '…',
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: PA.text,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          height: 1.3)),
                ),
                for (final off in [1, 2])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(lineAt(idx + off),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: PA.textSecondary, fontSize: 15)),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _FavButton extends StatefulWidget {
  final Track track;
  final double size;
  const _FavButton({required this.track, required this.size});
  @override
  State<_FavButton> createState() => _FavButtonState();
}

class _FavButtonState extends State<_FavButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
  // Overshoot-and-settle so favoriting gives a satisfying little pop.
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0), weight: 60),
  ]).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _toggle(dynamic pl) {
    final becomingFav = !pl.isFavorite(widget.track);
    HapticFeedback.lightImpact();
    pl.toggleFavorite(widget.track);
    if (becomingFav) _c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final pl = context.read<AppState>().playlists;
    return AnimatedBuilder(
      animation: pl,
      builder: (_, _) {
        final fav = pl.isFavorite(widget.track);
        return IconButton(
          icon: ScaleTransition(
            scale: _scale,
            child: Icon(fav ? Icons.favorite : Icons.favorite_border,
                size: widget.size, color: fav ? PA.accent : PA.textSecondary),
          ),
          onPressed: () => _toggle(pl),
        );
      },
    );
  }
}

// ── Shared player widgets (also used by dialogs) ─────────────────────────────

class SeekBar extends StatefulWidget {
  final PlayerService ps;
  final Track? track; // enables the waveform when the source is on-device
  const SeekBar({super.key, required this.ps, this.track});
  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _dragValue; // seconds; non-null while the thumb is being dragged
  bool _remaining = false; // right label shows -remaining instead of total
  List<double>? _bars;
  String? _barsKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadBars();
  }

  @override
  void didUpdateWidget(covariant SeekBar old) {
    super.didUpdateWidget(old);
    if (old.track?.key != widget.track?.key) _loadBars();
  }

  void _loadBars() {
    final t = widget.track;
    if (t == null || !WaveformService.eligible(t)) {
      _bars = null;
      _barsKey = null;
      return;
    }
    if (_barsKey == t.key) return;
    _barsKey = t.key;
    _bars = null;
    context.read<AppState>().waveforms?.forTrack(t).then((bars) {
      if (mounted && _barsKey == t.key) setState(() => _bars = bars);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Boundary keeps the ~5x/s position updates repainting only the bar.
    return RepaintBoundary(
      child: StreamBuilder<Duration?>(
        stream: widget.ps.duration,
        builder: (_, durSnap) {
          final total = durSnap.data?.inMilliseconds.toDouble() ?? 0;
          return StreamBuilder<Duration>(
            stream: widget.ps.position,
            builder: (_, posSnap) {
              final pos = posSnap.data?.inMilliseconds.toDouble() ?? 0;
              final max = total > 0 ? total : 1.0;
              final value = (_dragValue ?? pos).clamp(0.0, max);
              final control = _bars != null
                  ? _WaveformBar(
                      bars: _bars!,
                      progress: (value / max).clamp(0.0, 1.0),
                      enabled: total > 0,
                      onScrub: (f) =>
                          setState(() => _dragValue = f * max),
                      onScrubEnd: (f) {
                        widget.ps
                            .seek(Duration(milliseconds: (f * max).round()));
                        setState(() => _dragValue = null);
                      },
                    )
                  : SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        // Track and thumb grow while scrubbing for feedback.
                        trackHeight: _dragValue != null ? 5 : 3,
                        thumbShape: RoundSliderThumbShape(
                            enabledThumbRadius:
                                _dragValue != null ? 8.5 : 6),
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
                    );
              return Column(
                children: [
                  control,
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(fmtDuration(value / 1000),
                            style: const TextStyle(
                                fontSize: 11, color: PA.textMuted)),
                        // Tap the right label to flip total ⇄ remaining.
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () =>
                              setState(() => _remaining = !_remaining),
                          child: Text(
                              _remaining
                                  ? '-${fmtDuration((total - value) / 1000)}'
                                  : fmtDuration(total / 1000),
                              style: const TextStyle(
                                  fontSize: 11, color: PA.textMuted)),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Namida-style waveform seekbar: amplitude bars, played portion in accent,
/// draggable/tappable to scrub. One CustomPaint, ~96 rects — trivially cheap.
class _WaveformBar extends StatelessWidget {
  final List<double> bars;
  final double progress;
  final bool enabled;
  final void Function(double fraction) onScrub;
  final void Function(double fraction) onScrubEnd;
  const _WaveformBar({
    required this.bars,
    required this.progress,
    required this.enabled,
    required this.onScrub,
    required this.onScrubEnd,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        double frac(Offset p) => (p.dx / c.maxWidth).clamp(0.0, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: enabled ? (d) => onScrubEnd(frac(d.localPosition)) : null,
          onHorizontalDragUpdate:
              enabled ? (d) => onScrub(frac(d.localPosition)) : null,
          onHorizontalDragEnd: enabled
              ? (d) => onScrubEnd(progress) // last scrubbed fraction
              : null,
          child: SizedBox(
            height: 48,
            width: double.infinity,
            child: CustomPaint(
              painter: _WaveformPainter(bars: bars, progress: progress),
            ),
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> bars;
  final double progress;
  _WaveformPainter({required this.bars, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final n = bars.length;
    final slot = size.width / n;
    final barW = slot * 0.62;
    final mid = size.height / 2;
    final played = Paint()..color = PA.accent;
    final rest = Paint()..color = PA.card;
    final cut = progress * n;
    for (var i = 0; i < n; i++) {
      final h = (bars[i] * (size.height - 6)).clamp(2.0, size.height - 6);
      final x = i * slot + (slot - barW) / 2;
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, mid - h / 2, barW, h),
        const Radius.circular(2),
      );
      canvas.drawRRect(r, i < cut ? played : rest);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress || !identical(old.bars, bars);
}

class TransportControls extends StatefulWidget {
  final PlayerService ps;
  const TransportControls({super.key, required this.ps});

  @override
  State<TransportControls> createState() => _TransportControlsState();
}

class _TransportControlsState extends State<TransportControls> {
  PlayerService get ps => widget.ps;
  Timer? _holdSeek;

  @override
  void dispose() {
    _holdSeek?.cancel();
    super.dispose();
  }

  /// Holding prev/next scrubs the current track in configurable hops,
  /// Namida-style. [dir] is -1 (rewind) or 1 (fast-forward).
  void _startHoldSeek(int dir) {
    _holdSeek?.cancel();
    void hop() {
      final step = ps.settings?.holdSeekSec ?? 5;
      final pos = ps.player.position + Duration(seconds: dir * step);
      final max = ps.player.duration ?? Duration.zero;
      ps.player.seek(pos < Duration.zero
          ? Duration.zero
          : (max > Duration.zero && pos > max ? max : pos));
    }

    hop();
    _holdSeek =
        Timer.periodic(const Duration(milliseconds: 250), (_) => hop());
  }

  void _stopHoldSeek() {
    _holdSeek?.cancel();
    _holdSeek = null;
  }

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
        GestureDetector(
          onLongPressStart: (_) => _startHoldSeek(-1),
          onLongPressEnd: (_) => _stopHoldSeek(),
          onLongPressCancel: _stopHoldSeek,
          child: _PressScale(
            child: IconButton(
              icon: const Icon(Icons.skip_previous, size: 38),
              color: Colors.white,
              onPressed: ps.previousSmart,
            ),
          ),
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
              child: _PressScale(
                child: Container(
                  width: 68,
                  height: 68,
                  // Without this the glyph paints at the circle's top-left.
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                  child: buffering
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(
                              strokeWidth: 3, color: Colors.black))
                      : _AnimatedPlayPause(
                          playing: playing, size: 40, color: Colors.black),
                ),
              ),
            );
          },
        ),
        GestureDetector(
          onLongPressStart: (_) => _startHoldSeek(1),
          onLongPressEnd: (_) => _stopHoldSeek(),
          onLongPressCancel: _stopHoldSeek,
          child: _PressScale(
            child: IconButton(
              icon: const Icon(Icons.skip_next, size: 38),
              color: Colors.white,
              onPressed: ps.next,
            ),
          ),
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

class _QueueSheet extends StatelessWidget {
  final PlayerService ps;
  const _QueueSheet({required this.ps});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.65,
      child: QueuePanel(ps: ps),
    );
  }
}

/// The queue list itself — shared by the modal sheet and the in-player
/// slide-up panel. Reorder, swipe-to-remove with undo, tap-to-jump.
class QueuePanel extends StatefulWidget {
  final PlayerService ps;
  const QueuePanel({super.key, required this.ps});
  @override
  State<QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends State<QueuePanel> {
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
    return ValueListenableBuilder<int>(
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
                            'except' => await ps.removeAllExceptCurrent(),
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
                          PopupMenuItem(
                              value: 'except',
                              child: Text('Remove all except current')),
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
                    onReorder: (from, to) {
                      if (to > from) to -= 1; // ReorderableListView index convention
                      HapticFeedback.lightImpact();
                      ps.moveInQueue(from, to);
                    },
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
    );
  }
}
