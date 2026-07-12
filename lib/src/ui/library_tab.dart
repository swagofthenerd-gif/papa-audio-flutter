import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../local_library.dart';
import '../models.dart';
import '../theme.dart';
import 'playlists_ui.dart';
import 'track_tile.dart';
import 'widgets.dart';

enum TrackSort { title, artist, album, dateAdded, duration }

/// On-phone library, Namida-style breadth in Spotify clothes: chip tabs for
/// Tracks / Albums / Artists / Folders / Playlists / History / Most Played,
/// with per-tab search, sorting, and a shuffle-all action.
class LibraryTab extends StatefulWidget {
  const LibraryTab({super.key});
  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<LibraryTab>
    with SingleTickerProviderStateMixin {
  static const _tabs = [
    'Tracks', 'Albums', 'Artists', 'Folders', 'Playlists', 'History', 'Most played'
  ];
  late final TabController _tc = TabController(length: _tabs.length, vsync: this);
  final _searchCtrl = TextEditingController();
  String _query = '';
  TrackSort _sort = TrackSort.title;
  bool _sortReverse = false;

  @override
  void dispose() {
    _tc.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.read<AppState>().localLibrary;
    return AnimatedBuilder(
      animation: lib,
      builder: (context, _) {
        if (!lib.permitted) return _PermissionPrompt(lib: lib);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (v) =>
                            setState(() => _query = v.trim().toLowerCase()),
                        decoration: InputDecoration(
                          hintText: 'Search your library…',
                          hintStyle: const TextStyle(fontSize: 13),
                          filled: true,
                          fillColor: PA.card,
                          isDense: true,
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _query = '');
                                  },
                                ),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sort',
                    icon: const Icon(Icons.sort, size: 20),
                    onPressed: _showSortMenu,
                  ),
                  IconButton(
                    tooltip: 'Shuffle all',
                    icon: const Icon(Icons.shuffle, size: 20, color: PA.accent),
                    onPressed: () {
                      final tracks = _filteredTracks(lib);
                      context.read<AppState>().playerService.playShuffled(tracks);
                    },
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tc,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerColor: Colors.transparent,
              indicatorColor: PA.accent,
              labelColor: PA.accent,
              unselectedLabelColor: PA.textSecondary,
              labelStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: [for (final t in _tabs) Tab(text: t, height: 40)],
            ),
            Expanded(
              child: TabBarView(
                controller: _tc,
                children: [
                  _TracksView(
                      lib: lib,
                      query: _query,
                      sort: _sort,
                      reverse: _sortReverse),
                  _AlbumsView(lib: lib, query: _query),
                  _ArtistsView(lib: lib, query: _query),
                  _FoldersView(lib: lib, query: _query),
                  PlaylistsView(query: _query),
                  HistoryView(query: _query),
                  MostPlayedView(query: _query),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  List<Track> _filteredTracks(LocalLibrary lib) {
    final all = lib.albums.expand((a) => a.tracks).toList();
    if (_query.isEmpty) return all;
    return all.where((t) => _match(t, _query)).toList();
  }

  void _showSortMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: PA.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('Sort tracks by',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            for (final (s, label) in [
              (TrackSort.title, 'Title'),
              (TrackSort.artist, 'Artist'),
              (TrackSort.album, 'Album'),
              (TrackSort.dateAdded, 'Date added'),
              (TrackSort.duration, 'Duration'),
            ])
              ListTile(
                dense: true,
                leading: Icon(
                    _sort == s
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: _sort == s ? PA.accent : PA.textMuted,
                    size: 20),
                title: Text(label),
                onTap: () {
                  setState(() => _sort = s);
                  Navigator.pop(sheetCtx);
                },
              ),
            SwitchListTile(
              dense: true,
              activeThumbColor: PA.accent,
              title: const Text('Reverse order'),
              value: _sortReverse,
              onChanged: (v) {
                setState(() => _sortReverse = v);
                Navigator.pop(sheetCtx);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

bool _match(Track t, String q) =>
    t.title.toLowerCase().contains(q) ||
    t.artist.toLowerCase().contains(q) ||
    (t.album ?? '').toLowerCase().contains(q) ||
    t.filePath.toLowerCase().contains(q);

// ── Tracks ────────────────────────────────────────────────────────────────────

class _TracksView extends StatelessWidget {
  final LocalLibrary lib;
  final String query;
  final TrackSort sort;
  final bool reverse;
  const _TracksView(
      {required this.lib,
      required this.query,
      required this.sort,
      required this.reverse});

  @override
  Widget build(BuildContext context) {
    var tracks = lib.albums.expand((a) => a.tracks).toList();
    if (query.isNotEmpty) tracks = tracks.where((t) => _match(t, query)).toList();
    tracks.sort(_comparator);
    if (reverse) tracks = tracks.reversed.toList();
    if (tracks.isEmpty) return const _Empty('No tracks');
    final s = context.read<AppState>();
    return Scrollbar(
      interactive: true,
      thickness: 6,
      radius: const Radius.circular(3),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: tracks.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('${tracks.length} tracks',
                  style: const TextStyle(color: PA.textMuted, fontSize: 12)),
            );
          }
          final t = tracks[i - 1];
          return TrackTile(
              track: t, onTap: () => s.playTrackInList(tracks, i - 1));
        },
      ),
    );
  }

  int Function(Track, Track) get _comparator => switch (sort) {
        TrackSort.title => (a, b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        TrackSort.artist => (a, b) =>
            a.artist.toLowerCase().compareTo(b.artist.toLowerCase()),
        TrackSort.album => (a, b) =>
            (a.album ?? '').toLowerCase().compareTo((b.album ?? '').toLowerCase()),
        TrackSort.dateAdded => (a, b) => b.id.compareTo(a.id),
        TrackSort.duration => (a, b) => b.duration.compareTo(a.duration),
      };
}

// ── Albums ────────────────────────────────────────────────────────────────────

class _AlbumsView extends StatelessWidget {
  final LocalLibrary lib;
  final String query;
  const _AlbumsView({required this.lib, required this.query});

  @override
  Widget build(BuildContext context) {
    var albums = lib.albums;
    if (query.isNotEmpty) {
      albums = albums
          .where((a) =>
              a.name.toLowerCase().contains(query) ||
              a.artist.toLowerCase().contains(query))
          .toList();
    }
    if (albums.isEmpty) return const _Empty('No albums');
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.78,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12),
      itemCount: albums.length,
      itemBuilder: (_, i) => _LocalAlbumCard(album: albums[i]),
    );
  }
}

class _LocalAlbumCard extends StatelessWidget {
  final LocalAlbum album;
  const _LocalAlbumCard({required this.album});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => LocalAlbumScreen(album: album))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (_, c) => TrackArt(
                artUri: 'localart://${album.artTrackId}/${album.albumId}',
                size: c.maxWidth,
                radius: 6,
                px: 300,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(album.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Text(album.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: PA.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}

class LocalAlbumScreen extends StatelessWidget {
  final LocalAlbum album;
  const LocalAlbumScreen({super.key, required this.album});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: PA.background,
            flexibleSpace: FlexibleSpaceBar(
              background: LayoutBuilder(
                builder: (_, c) => TrackArt(
                  artUri: 'localart://${album.artTrackId}/${album.albumId}',
                  size: c.maxWidth,
                  radius: 0,
                  px: 800,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(album.name,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                  Text(album.artist,
                      style: const TextStyle(color: PA.textSecondary)),
                  const SizedBox(height: 12),
                  PlayShuffleRow(tracks: album.tracks),
                ],
              ),
            ),
          ),
          SliverList.builder(
            itemCount: album.tracks.length,
            itemBuilder: (_, i) {
              final t = album.tracks[i];
              return TrackTile(
                track: t,
                showArt: false,
                leading: SizedBox(
                    width: 24,
                    child: Center(
                        child: Text('${i + 1}',
                            style: const TextStyle(color: PA.textMuted)))),
                onTap: () => s.playTrackInList(album.tracks, i),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }
}

// ── Artists ───────────────────────────────────────────────────────────────────

class _ArtistsView extends StatelessWidget {
  final LocalLibrary lib;
  final String query;
  const _ArtistsView({required this.lib, required this.query});

  @override
  Widget build(BuildContext context) {
    final byArtist = <String, List<Track>>{};
    for (final t in lib.albums.expand((a) => a.tracks)) {
      byArtist.putIfAbsent(t.artist, () => []).add(t);
    }
    var names = byArtist.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (query.isNotEmpty) {
      names = names.where((n) => n.toLowerCase().contains(query)).toList();
    }
    if (names.isEmpty) return const _Empty('No artists');
    return ListView.builder(
      itemCount: names.length,
      itemBuilder: (_, i) {
        final name = names[i];
        final tracks = byArtist[name]!;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: PA.card,
            child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                style: const TextStyle(color: PA.accent)),
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${tracks.length} tracks',
              style: const TextStyle(color: PA.textMuted, fontSize: 12)),
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      TrackListScreen(title: name, tracks: tracks))),
        );
      },
    );
  }
}

// ── Folders ───────────────────────────────────────────────────────────────────

class _FoldersView extends StatelessWidget {
  final LocalLibrary lib;
  final String query;
  const _FoldersView({required this.lib, required this.query});

  @override
  Widget build(BuildContext context) {
    final byFolder = <String, List<Track>>{};
    for (final t in lib.albums.expand((a) => a.tracks)) {
      if (t.filePath.isEmpty) continue;
      final sep = t.filePath.contains('/') ? '/' : r'\';
      final idx = t.filePath.lastIndexOf(sep);
      final dir = idx > 0 ? t.filePath.substring(0, idx) : t.filePath;
      byFolder.putIfAbsent(dir, () => []).add(t);
    }
    var dirs = byFolder.keys.toList()..sort(_numericAwareCompare);
    if (query.isNotEmpty) {
      dirs = dirs.where((d) => d.toLowerCase().contains(query)).toList();
    }
    if (dirs.isEmpty) return const _Empty('No folders');
    return ListView.builder(
      itemCount: dirs.length,
      itemBuilder: (_, i) {
        final dir = dirs[i];
        final tracks = byFolder[dir]!;
        final name = dir.split(RegExp(r'[\\/]')).last;
        return ListTile(
          leading: const Icon(Icons.folder, color: PA.warning),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('$dir · ${tracks.length} tracks',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: PA.textMuted, fontSize: 11)),
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      TrackListScreen(title: name, tracks: tracks))),
        );
      },
    );
  }

  /// "Music 2" sorts before "Music 12" — compares digit runs numerically.
  static int _numericAwareCompare(String a, String b) {
    final ra = RegExp(r'(\d+)|(\D+)');
    final pa = ra.allMatches(a.toLowerCase()).map((m) => m.group(0)!).toList();
    final pb = ra.allMatches(b.toLowerCase()).map((m) => m.group(0)!).toList();
    for (var i = 0; i < pa.length && i < pb.length; i++) {
      final na = int.tryParse(pa[i]);
      final nb = int.tryParse(pb[i]);
      final c = (na != null && nb != null)
          ? na.compareTo(nb)
          : pa[i].compareTo(pb[i]);
      if (c != 0) return c;
    }
    return pa.length.compareTo(pb.length);
  }
}

// ── Shared pieces ─────────────────────────────────────────────────────────────

/// Generic "list of tracks" screen used by artists, folders, history days…
class TrackListScreen extends StatelessWidget {
  final String title;
  final List<Track> tracks;
  const TrackListScreen({super.key, required this.title, required this.tracks});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: PA.background,
        title: Text(title, style: const TextStyle(fontSize: 17)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: PlayShuffleRow(tracks: tracks),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: tracks.length,
              itemBuilder: (_, i) => TrackTile(
                  track: tracks[i],
                  onTap: () => s.playTrackInList(tracks, i)),
            ),
          ),
        ],
      ),
    );
  }
}

class PlayShuffleRow extends StatelessWidget {
  final List<Track> tracks;
  const PlayShuffleRow({super.key, required this.tracks});
  @override
  Widget build(BuildContext context) {
    final ps = context.read<AppState>().playerService;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: PA.accent),
          onPressed:
              tracks.isEmpty ? null : () => ps.playQueue(tracks, 0),
          icon: const Icon(Icons.play_arrow, color: Colors.black),
          label: const Text('Play',
              style:
                  TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
              foregroundColor: PA.accent,
              side: const BorderSide(color: PA.accent)),
          onPressed: tracks.isEmpty ? null : () => ps.playShuffled(tracks),
          icon: const Icon(Icons.shuffle, size: 18),
          label: const Text('Shuffle'),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  final String message;
  const _Empty(this.message);
  @override
  Widget build(BuildContext context) => Center(
      child:
          Text(message, style: const TextStyle(color: PA.textSecondary)));
}

class _PermissionPrompt extends StatelessWidget {
  final LocalLibrary lib;
  const _PermissionPrompt({required this.lib});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.library_music, color: PA.textMuted, size: 48),
          const SizedBox(height: 14),
          const Text('Your on-phone music',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
                'Papa Audio needs permission to read the music stored on this phone.',
                textAlign: TextAlign.center,
                style: TextStyle(color: PA.textSecondary)),
          ),
          const SizedBox(height: 18),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: PA.accent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14)),
            onPressed: lib.requestAndLoad,
            child: const Text('Allow access',
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
