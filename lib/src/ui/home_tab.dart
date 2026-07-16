import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../main.dart' show AlbumScreen; // PC album detail screen
import '../app_state.dart';
import '../local_library.dart';
import '../models.dart';
import '../playlists.dart';
import '../queues_store.dart';
import '../recommendations.dart';
import '../theme.dart';
import 'collection_menu.dart';
import 'dialogs.dart';
import 'library_tab.dart';
import 'playlists_ui.dart';
import 'recently_added.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'widgets.dart';

/// Home: a made-for-you landing page. On top of the library shelves it now
/// carries on-device recommendations — Jump back in, generated mixes, forgotten
/// favorites, time-of-day and year rotations — all computed from listening
/// history (see RecommendationService), plus a Spotify-style quick-picks grid.
/// Shelves hide themselves when empty so the page is never padded with blanks.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  // Derived library shelves are memoized by source revisions — a listen tick or
  // download progress event must never recompute rankings or album sorts.
  List<Track> _recent = const [];
  List<LocalAlbum> _recentlyAdded = const [];
  String _sig = '';

  void _recompute(AppState s) {
    final sig = '${s.history.revision}|${s.localLibrary.revision}';
    if (sig == _sig) return;
    _sig = sig;
    _recent = s.history.recentTracks(limit: 20);
    _recentlyAdded = _recentlyAddedAlbums(s.localLibrary);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return AnimatedBuilder(
      animation: Listenable.merge([
        s,
        s.history,
        s.localLibrary,
        s.playlists,
        s.queues,
        s.recommendations,
      ]),
      builder: (context, _) {
        _recompute(s);
        // Fire-and-forget: no-ops unless inputs or the day changed.
        s.recommendations
            .refresh(s.history, s.localLibrary, s.playlists, s.settings);

        final recent = _recent;
        final recentlyAdded = _recentlyAdded;
        final localAlbums = s.localLibrary.albums;
        final firstIndexing = s.localLibrary.permitted &&
            s.localLibrary.loading &&
            localAlbums.isEmpty;

        return RefreshIndicator(
          color: PA.accent,
          onRefresh: () async {
            await s.localLibrary.refresh();
            if (s.configured) await s.loadLibrary();
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _Header()),
              SliverToBoxAdapter(child: _QuickPicks(state: s)),

              if (firstIndexing) const _SkeletonShelves(),

              // Jump back in — resumable albums/playlists, position-accurate.
              SliverToBoxAdapter(child: _JumpBackIn(state: s)),

              // On-device recommendation shelves (mixes, rotations, etc).
              for (final shelf in s.recommendations.shelves)
                _RecoShelfView(shelf: shelf),

              if (recent.isNotEmpty)
                _Shelf(
                  title: 'Recently played',
                  onSeeAll: () => _openTracks(context, 'Recently played', recent),
                  child: _TrackRow(tracks: recent),
                ),
              if (recentlyAdded.isNotEmpty)
                _Shelf(
                  title: 'Recently added',
                  onSeeAll: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const RecentlyAddedScreen())),
                  child: _LocalAlbumRow(albums: recentlyAdded),
                ),
              if (s.playlists.playlists.isNotEmpty)
                _Shelf(
                  title: 'Your playlists',
                  child: _PlaylistRow(playlists: s.playlists.playlists),
                ),
              if (localAlbums.isNotEmpty)
                _Shelf(
                  title: 'On your phone',
                  child: _LocalAlbumRow(albums: localAlbums),
                ),
              if (s.albums.isNotEmpty)
                _Shelf(
                  title: 'From your PC',
                  child: _PcAlbumRow(albums: s.albums),
                ),
              if (s.queues.saved.isNotEmpty)
                _Shelf(
                  title: 'Recent queues',
                  child: _QueueRow(queues: s.queues.saved),
                ),

              if (!firstIndexing &&
                  recent.isEmpty &&
                  localAlbums.isEmpty &&
                  s.albums.isEmpty)
                SliverToBoxAdapter(child: _EmptyHome(state: s)),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        );
      },
    );
  }

  static List<LocalAlbum> _recentlyAddedAlbums(LocalLibrary lib) {
    final keyed = [
      for (final al in lib.albums)
        (al.tracks.fold(0, (m, t) => t.dateAdded > m ? t.dateAdded : m), al)
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final k in keyed.take(15)) k.$2];
  }

  static void _openTracks(BuildContext context, String title, List<Track> t) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => TrackListScreen(title: title, tracks: t)));
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  static const _months = [
    'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE', 'JULY',
    'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'
  ];
  static const _weekdays = [
    'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final hour = now.hour;
    final greeting = hour < 5
        ? 'Late night'
        : hour < 12
            ? 'Good morning'
            : hour < 17
                ? 'Good afternoon'
                : hour < 22
                    ? 'Good evening'
                    : 'Night owl';
    final eyebrow = '${_weekdays[now.weekday - 1]}, ${_months[now.month - 1]} ${now.day}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(eyebrow,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: PA.textMuted)),
                const SizedBox(height: 2),
                Text(greeting,
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: PA.text)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded, color: PA.textSecondary),
            tooltip: 'Your stats',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const StatsScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.history, color: PA.textSecondary),
            tooltip: 'Listening history',
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => Scaffold(
                          appBar: AppBar(
                              backgroundColor: PA.background,
                              title: const Text('History',
                                  style: TextStyle(fontSize: 17))),
                          body: const HistoryView(query: ''),
                        ))),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: PA.textSecondary),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
    );
  }
}

// ── Quick picks (2-column Spotify-style tiles) ───────────────────────────────

class _QuickPicks extends StatelessWidget {
  final AppState state;
  const _QuickPicks({required this.state});

  @override
  Widget build(BuildContext context) {
    final favs = state.playlists.favorites;
    final picks = <_Pick>[
      _Pick('Liked Songs', Icons.favorite, const [PA.accent, Color(0xFF0E5A2B)],
          () => _open(context, 'Liked Songs', favs)),
      _Pick('History', Icons.history, const [Color(0xFF3A5BA0), Color(0xFF1E2E52)],
          () => _open(context, 'History', state.history.recentTracks(limit: 100))),
      _Pick('Most played', Icons.local_fire_department,
          const [Color(0xFFB5442A), Color(0xFF5A2015)],
          () => _open(context, 'Most played',
              state.history.mostPlayed(limit: 100).map((e) => e.$1).toList())),
      _Pick('Recently added', Icons.new_releases,
          const [Color(0xFF7A3FA0), Color(0xFF3A1E52)],
          () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const RecentlyAddedScreen()))),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 2.9,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        children: [for (final p in picks) _PickTile(pick: p)],
      ),
    );
  }

  void _open(BuildContext context, String title, List<Track> tracks) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => TrackListScreen(title: title, tracks: tracks)));
  }
}

class _Pick {
  final String label;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;
  _Pick(this.label, this.icon, this.gradient, this.onTap);
}

class _PickTile extends StatelessWidget {
  final _Pick pick;
  const _PickTile({required this.pick});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(PA.rMd),
        onTap: pick.onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: pick.gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(PA.rMd),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(pick.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ),
              Icon(pick.icon, color: Colors.white70, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Jump back in ──────────────────────────────────────────────────────────────

class _JumpBackIn extends StatefulWidget {
  final AppState state;
  const _JumpBackIn({required this.state});
  @override
  State<_JumpBackIn> createState() => _JumpBackInState();
}

class _JumpBackInState extends State<_JumpBackIn> {
  List<JumpBackItem> _items = const [];
  String _sig = '';

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    // Resolve against the freshest queue/library/playlist state.
    final sig = '${s.playerService.queueRevision.value}|${s.albums.length}|'
        '${s.localLibrary.revision}|${s.playlists.revision}';
    if (sig != _sig) {
      _sig = sig;
      s.jumpBackIn().then((v) {
        if (mounted) setState(() => _items = v);
      });
    }
    if (_items.isEmpty) return const SizedBox.shrink();
    return _Shelf(
      title: 'Jump back in',
      child: _Row(children: [
        for (final it in _items)
          _Card(
            artUri: it.artUri,
            artPath: it.artPath,
            title: it.title,
            subtitle: it.subtitle,
            onTap: () => s.resumeJumpBack(it),
            onLongPress: () =>
                showCollectionMenu(context, title: it.title, tracks: it.tracks),
          ),
      ]),
    );
  }
}

// ── Recommendation shelves ────────────────────────────────────────────────────

class _RecoShelfView extends StatelessWidget {
  final RecoShelf shelf;
  const _RecoShelfView({required this.shelf});
  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    if (shelf.kind == RecoKind.mixes) {
      return _Shelf(
        title: shelf.title,
        kicker: shelf.kicker,
        child: _Row(children: [
          for (final mix in shelf.mixes)
            _Card(
              artUri: mix.tracks.first.artUri,
              artPath: mix.tracks.first.artPath,
              title: mix.title,
              subtitle: mix.subtitle,
              onTap: () => s.playMix(mix.tracks),
              onLongPress: () => showCollectionMenu(context,
                  title: mix.title, tracks: mix.tracks),
            ),
        ]),
      );
    }
    return _Shelf(
      title: shelf.title,
      kicker: shelf.kicker,
      onSeeAll: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => TrackListScreen(title: shelf.title, tracks: shelf.tracks))),
      child: _TrackRow(tracks: shelf.tracks),
    );
  }
}

// ── Shelf scaffolding ─────────────────────────────────────────────────────────

class _Shelf extends StatelessWidget {
  final String title;
  final String? kicker;
  final VoidCallback? onSeeAll;
  final Widget child;
  const _Shelf(
      {required this.title, this.kicker, this.onSeeAll, required this.child});

  @override
  Widget build(BuildContext context) {
    final header = Padding(
      padding: EdgeInsets.fromLTRB(16, kicker != null ? 18 : 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (kicker != null)
                  Text(kicker!,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: PA.textMuted)),
                Text(title,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4)),
              ],
            ),
          ),
          if (onSeeAll != null)
            const Icon(Icons.chevron_right, color: PA.textSecondary),
        ],
      ),
    );
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Whole header row is tappable when there's a destination (bigger
          // target than a tiny "See all" text button).
          onSeeAll != null
              ? InkWell(onTap: onSeeAll, child: header)
              : header,
          child,
        ],
      ),
    );
  }
}

/// Square-art card used for track and album shelves. Ripple + long-press menu
/// so a shelf card behaves like a track/collection anywhere else in the app.
class _Card extends StatelessWidget {
  final String? artUri;
  final String? artPath;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _Card({
    this.artUri,
    this.artPath,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    // Text-scale-safe height: art + gap + two text lines at the current scale.
    final scaler = MediaQuery.textScalerOf(context);
    final textBlock = scaler.scale(13) + scaler.scale(11) + 6;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(PA.rMd),
        onTap: onTap,
        onLongPress: onLongPress == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onLongPress!();
              },
        child: SizedBox(
          width: 138,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(PA.rMd),
                child: TrackArt(
                    artUri: artUri, artPath: artPath, size: 138, radius: PA.rMd, px: 300),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: textBlock,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: PA.textSecondary, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final List<Widget> children;
  const _Row({required this.children});
  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final height = 138 + 6 + scaler.scale(13) + scaler.scale(11) + 8;
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => children[i],
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  final List<Track> tracks;
  const _TrackRow({required this.tracks});
  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return _Row(children: [
      for (var i = 0; i < tracks.length; i++)
        _Card(
          artUri: tracks[i].artUri,
          artPath: tracks[i].artPath,
          title: tracks[i].title,
          subtitle: tracks[i].artist,
          onTap: () => _playWithUndo(context, s, tracks, i),
          onLongPress: () => showTrackMenu(context, tracks[i]),
        ),
    ]);
  }
}

/// Replacing the queue from a shelf tap is easy to do by accident — offer undo
/// by snapshotting the current queue first.
void _playWithUndo(
    BuildContext context, AppState s, List<Track> tracks, int index) {
  final prevQueue = List<Track>.of(s.playerService.queue);
  final prevIndex = s.playerService.player.currentIndex ?? 0;
  s.playTrackInList(tracks, index);
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(SnackBar(
    content: Text('Playing ${tracks[index].title}'),
    duration: const Duration(seconds: 3),
    action: prevQueue.isEmpty
        ? null
        : SnackBarAction(
            label: 'Undo',
            onPressed: () => s.playerService.playQueue(prevQueue, prevIndex),
          ),
  ));
}

class _LocalAlbumRow extends StatelessWidget {
  final List<LocalAlbum> albums;
  const _LocalAlbumRow({required this.albums});
  @override
  Widget build(BuildContext context) {
    return _Row(children: [
      for (final a in albums)
        _Card(
          artUri: 'localart://${a.artTrackId}/${a.albumId}',
          title: a.name,
          subtitle: a.artist,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => LocalAlbumScreen(album: a))),
          onLongPress: () =>
              showCollectionMenu(context, title: a.name, tracks: a.tracks),
        ),
    ]);
  }
}

class _PcAlbumRow extends StatelessWidget {
  final List<Album> albums;
  const _PcAlbumRow({required this.albums});
  @override
  Widget build(BuildContext context) {
    return _Row(children: [
      for (final a in albums)
        _Card(
          artPath: a.artPath,
          title: a.name,
          subtitle: a.artist,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => AlbumScreen(album: a))),
          onLongPress: () =>
              showCollectionMenu(context, title: a.name, tracks: a.tracks),
        ),
    ]);
  }
}

class _PlaylistRow extends StatelessWidget {
  final List<Playlist> playlists;
  const _PlaylistRow({required this.playlists});
  @override
  Widget build(BuildContext context) {
    return _Row(children: [
      for (final p in playlists)
        _Card(
          artUri: p.tracks.isNotEmpty ? p.tracks.first.artUri : null,
          artPath: p.tracks.isNotEmpty ? p.tracks.first.artPath : null,
          title: p.name,
          subtitle: '${p.tracks.length} tracks',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => PlaylistScreen(playlist: p))),
          onLongPress: p.tracks.isEmpty
              ? null
              : () => showCollectionMenu(context, title: p.name, tracks: p.tracks),
        ),
    ]);
  }
}

class _QueueRow extends StatelessWidget {
  final List<SavedQueue> queues;
  const _QueueRow({required this.queues});
  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return _Row(children: [
      for (final q in queues)
        _Card(
          artUri: q.tracks.first.artUri,
          artPath: q.tracks.first.artPath,
          // Content first (a real track), count secondary — a timestamp gives
          // each queue card a distinct identity.
          title: q.tracks.first.title,
          subtitle: '${_when(q.at)} · ${q.tracks.length} tracks',
          onTap: () => s.playerService.playQueue(q.tracks, 0),
          onLongPress: () => showCollectionMenu(context,
              title: '${q.tracks.length}-track queue', tracks: q.tracks),
        ),
    ]);
  }

  static String _when(int ms) {
    final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${d.inDays ~/ 7}w ago';
  }
}

// ── Skeleton loading ──────────────────────────────────────────────────────────

class _SkeletonShelves extends StatelessWidget {
  const _SkeletonShelves();
  @override
  Widget build(BuildContext context) {
    Widget block(double w, double h) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
            color: PA.card, borderRadius: BorderRadius.circular(PA.rMd)));
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var shelf = 0; shelf < 2; shelf++) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
              child: block(160, 22),
            ),
            SizedBox(
              height: 176,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 4,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    block(138, 138),
                    const SizedBox(height: 8),
                    block(100, 12),
                    const SizedBox(height: 6),
                    block(70, 10),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyHome extends StatelessWidget {
  final AppState state;
  const _EmptyHome({required this.state});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
      child: Column(
        children: [
          const Icon(Icons.library_music, color: PA.textMuted, size: 56),
          const SizedBox(height: 16),
          const Text('Nothing to show yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'Grant music access to see your on-phone songs, or connect your '
              'PC to stream your library.',
              textAlign: TextAlign.center,
              style: TextStyle(color: PA.textSecondary)),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: PA.accent),
                icon: const Icon(Icons.folder_open),
                label: const Text('Grant music access'),
                onPressed: () => state.localLibrary.requestAndLoad(),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.computer),
                label: const Text('Connect PC'),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
