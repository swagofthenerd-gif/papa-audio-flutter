import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

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

  /// Lyrics view replaces the artwork while on (toggled by double-tap or the
  /// lyrics button). Lives here so the morphing artwork can hide with it.
  final ValueNotifier<bool> lyricsOn = ValueNotifier(false);

  /// Video overlay on (YouTube tracks only). Playing a muxed stream through the
  /// video engine while just_audio is paused — see YtVideoController.
  final ValueNotifier<bool> videoOn = ValueNotifier(false);

  Color? _artColor; // dominant artwork color for the expanded background
  String? _artColorKey;

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
  void dispose() {
    lyricsOn.dispose();
    videoOn.dispose();
    _c.dispose();
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
      return;
    }
    s.artColors.forTrack(track).then((c) {
      if (mounted && _artColorKey == track.key) {
        setState(() => _artColor = c);
      }
    });
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
        // Lands 8px below the header row; the _FullPlayer placeholder brackets
        // this rect exactly so artwork never overlaps title or controls.
        final fullRect = Rect.fromLTWH(
            (size.width - fullSide) / 2, topInset + 56, fullSide, fullSide);

        return PopScope(
          canPop: !expanded,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _c.fling(velocity: -2.2);
          },
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
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
                      onTap: t < 0.1 ? () => _c.fling(velocity: 2.2) : null,
                      onVerticalDragUpdate: (d) => _onVDragUpdate(d, travel),
                      onVerticalDragEnd: (d) => _onVDragEnd(d, travel),
                      child: Container(
                        decoration: BoxDecoration(
                          // Expanded background tints toward the artwork's
                          // dominant color (subtle — Spotify-dark stays boss).
                          color: Color.lerp(
                              PA.surfaceElevated,
                              _artColor != null
                                  ? Color.lerp(
                                      PA.background, _artColor, 0.38)!
                                  : PA.background,
                              t),
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
                            // during the drag. Hidden while lyrics are showing
                            // in the expanded player.
                            Positioned.fromRect(
                              rect: artRect,
                              child: ValueListenableBuilder<bool>(
                                valueListenable: lyricsOn,
                                builder: (_, lyr, child) => Opacity(
                                    opacity: lyr && t > 0.5 ? 0 : 1,
                                    child: child),
                                child: ClipRRect(
                                  borderRadius:
                                      BorderRadius.circular(4 + 6 * t),
                                  child: FittedBox(
                                      fit: BoxFit.fill, child: art),
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
  const _FullPlayer(
      {required this.ps,
      required this.track,
      required this.topInset,
      required this.artSide,
      required this.lyricsOn,
      required this.videoOn,
      required this.onToggleVideo,
      required this.onCollapse});

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
                onPressed: () => showQueueSheet(context, ps),
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
                      child: Text(track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () {
                        onCollapse();
                        openArtist(context, context.read<AppState>(), track);
                      },
                      child: Text(track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                        Text(fmtDuration(total / 1000),
                            style: const TextStyle(
                                fontSize: 11, color: PA.textMuted)),
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
          child: IconButton(
            icon: const Icon(Icons.skip_previous, size: 38),
            color: Colors.white,
            onPressed: ps.previousSmart,
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
                    : _AnimatedPlayPause(
                        playing: playing, size: 40, color: Colors.black),
              ),
            );
          },
        ),
        GestureDetector(
          onLongPressStart: (_) => _startHoldSeek(1),
          onLongPressEnd: (_) => _stopHoldSeek(),
          onLongPressCancel: _stopHoldSeek,
          child: IconButton(
            icon: const Icon(Icons.skip_next, size: 38),
            color: Colors.white,
            onPressed: ps.next,
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
      ),
    );
  }
}
