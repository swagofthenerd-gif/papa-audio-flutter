import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../main.dart' show AlbumScreen; // PC album detail screen
import '../app_state.dart';
import '../local_library.dart';
import '../models.dart';
import '../playlists.dart';
import '../queues_store.dart';
import '../theme.dart';
import 'library_tab.dart';
import 'playlists_ui.dart';
import 'recently_added.dart';
import 'settings_screen.dart';
import 'widgets.dart';

/// Namida-style landing page: a quick-picks grid over a stack of horizontal
/// shelves (recently played, most played, recently added, playlists, on-phone,
/// from your PC, recent queues). Everything is built from data the app already
/// tracks, and shelves hide themselves when empty so the page is never padded
/// with blanks. Papa Audio's Spotify look throughout.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  // Derived shelves are memoized by source revisions — a listen tick or
  // download progress event must never recompute rankings or album sorts.
  // (Perf audit finding.)
  List<Track> _recent = const [];
  List<Track> _top = const [];
  List<LocalAlbum> _recentlyAdded = const [];
  String _sig = '';

  void _recompute(AppState s) {
    final sig = '${s.history.revision}|${s.localLibrary.revision}';
    if (sig == _sig) return;
    _sig = sig;
    _recent = s.history.recentTracks(limit: 20);
    _top = s.history.mostPlayed(limit: 20).map((e) => e.$1).toList();
    _recentlyAdded = _recentlyAddedAlbums(s.localLibrary);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    // Rebuild when any content source changes — each is its own notifier.
    return AnimatedBuilder(
      animation: Listenable.merge(
          [s, s.history, s.localLibrary, s.playlists, s.queues]),
      builder: (context, _) {
        _recompute(s);
        final recent = _recent;
        final top = _top;
        final recentlyAdded = _recentlyAdded;
        final localAlbums = s.localLibrary.albums;

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
              if (recent.isNotEmpty)
                _Shelf(
                  title: 'Recently played',
                  onSeeAll: () => _openTracks(context, 'Recently played', recent),
                  child: _TrackRow(tracks: recent),
                ),
              if (top.isNotEmpty)
                _Shelf(
                  title: 'Your top tracks',
                  onSeeAll: () => _openTracks(context, 'Your top tracks', top),
                  child: _TrackRow(tracks: top),
                ),
              if (recentlyAdded.isNotEmpty)
                _Shelf(
                  title: 'Recently added',
                  onSeeAll: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const RecentlyAddedScreen())),
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
              // Nothing indexed yet and no bridge — guide the user.
              if (recent.isEmpty &&
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
    // Newest date computed once per album (not per comparison), then sorted.
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
  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 5
        ? 'Late night'
        : hour < 12
            ? 'Good morning'
            : hour < 17
                ? 'Good afternoon'
                : hour < 22
                    ? 'Good evening'
                    : 'Night owl';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(greeting,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: PA.text)),
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
    final history = state.history.recentTracks(limit: 100);
    final most = state.history.mostPlayed(limit: 100).map((e) => e.$1).toList();
    final picks = <_Pick>[
      _Pick('Liked Songs', Icons.favorite, const [PA.accent, Color(0xFF0E5A2B)],
          () => _open(context, 'Liked Songs', favs)),
      _Pick('History', Icons.history, const [Color(0xFF3A5BA0), Color(0xFF1E2E52)],
          () => _open(context, 'History', history)),
      _Pick('Most played', Icons.local_fire_department,
          const [Color(0xFFB5442A), Color(0xFF5A2015)],
          () => _open(context, 'Most played', most)),
      _Pick('Recently added', Icons.new_releases,
          const [Color(0xFF7A3FA0), Color(0xFF3A1E52)],
          () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const RecentlyAddedScreen()))),
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
        borderRadius: BorderRadius.circular(8),
        onTap: pick.onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: pick.gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(8),
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

// ── Shelf scaffolding ─────────────────────────────────────────────────────────

class _Shelf extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;
  final Widget child;
  const _Shelf({required this.title, this.onSeeAll, required this.child});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                ),
                if (onSeeAll != null)
                  TextButton(
                    onPressed: onSeeAll,
                    child: const Text('See all',
                        style: TextStyle(color: PA.textSecondary, fontSize: 12)),
                  ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Square-art card used for track and album shelves.
class _Card extends StatelessWidget {
  final String? artUri;
  final String? artPath;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _Card({
    this.artUri,
    this.artPath,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 138,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: TrackArt(
                  artUri: artUri, artPath: artPath, size: 138, radius: 8, px: 300),
            ),
            const SizedBox(height: 6),
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text(subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: PA.textSecondary, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final List<Widget> children;
  const _Row({required this.children});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 192,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: children.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) => children[i],
        ),
      );
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
          onTap: () => s.playTrackInList(tracks, i),
        ),
    ]);
  }
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
          title: '${q.tracks.length} tracks',
          subtitle: q.tracks.first.title,
          onTap: () => s.playerService.playQueue(q.tracks, 0),
        ),
    ]);
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
              'Grant music access in the Library tab to see your on-phone '
              'songs, or connect your PC to stream your library.',
              textAlign: TextAlign.center,
              style: TextStyle(color: PA.textSecondary)),
        ],
      ),
    );
  }
}
