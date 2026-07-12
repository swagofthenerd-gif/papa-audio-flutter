import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../local_library.dart';
import '../models.dart';
import '../theme.dart';
import 'playlists_ui.dart';
import 'selection_bar.dart';
import 'settings_screen.dart';
import 'track_tile.dart';
import 'widgets.dart';

enum TrackSort { title, artist, album, year, dateAdded, duration, mostPlayed, firstListen }

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
    'Tracks', 'Albums', 'Artists', 'Genres', 'Folders', 'Playlists', 'Queues', 'History', 'Most played'
  ];
  late final TabController _tc = TabController(length: _tabs.length, vsync: this);
  final _searchCtrl = TextEditingController();
  String _query = '';
  TrackSort _sort = TrackSort.title;
  bool _sortReverse = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _tc.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Search re-filters ~250ms after typing stops, so keystrokes never race
  /// a full library re-sort.
  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = v.trim().toLowerCase());
    });
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
                        onChanged: _onSearchChanged,
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
                                    _debounce?.cancel();
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
                  IconButton(
                    tooltip: 'Settings',
                    icon: const Icon(Icons.settings_outlined, size: 20),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen())),
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
                  _GenresView(lib: lib, query: _query),
                  _FoldersView(lib: lib, query: _query),
                  PlaylistsView(query: _query),
                  QueuesView(query: _query),
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
              (TrackSort.year, 'Year'),
              (TrackSort.dateAdded, 'Date added'),
              (TrackSort.duration, 'Duration'),
              (TrackSort.mostPlayed, 'Most played'),
              (TrackSort.firstListen, 'First listen'),
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

class _TracksView extends StatefulWidget {
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
  State<_TracksView> createState() => _TracksViewState();
}

class _TracksViewState extends State<_TracksView>
    with AutomaticKeepAliveClientMixin {
  static const _rowHeight = 64.0;
  final _scroll = ScrollController();
  String? _railLetter; // letter under the finger while dragging the rail

  // Keep the state (scroll offset + memoized sort) alive across library
  // sub-tab switches — coming back to Tracks must be instant.
  @override
  bool get wantKeepAlive => true;

  // Filter + sort results are memoized: recomputed only when the inputs
  // actually change, never on incidental rebuilds (scroll, player events).
  List<Track> _tracks = const [];
  Map<String, int> _letterIndex = const {};
  String _sig = '';

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _recompute(AppState s) {
    // History-based sorts also refresh when listen data changes.
    final historyBased = widget.sort == TrackSort.mostPlayed ||
        widget.sort == TrackSort.firstListen;
    final sig =
        '${widget.query}|${widget.sort.index}|${widget.reverse}|${widget.lib.revision}'
        '${historyBased ? '|${s.history.revision}' : ''}';
    if (sig == _sig) return;
    _sig = sig;

    var tracks = widget.lib.albums.expand((a) => a.tracks).toList();
    if (widget.query.isNotEmpty) {
      tracks = tracks.where((t) => _match(t, widget.query)).toList();
    }
    tracks.sort(_comparator(s));
    if (widget.reverse) tracks = tracks.reversed.toList();
    _tracks = tracks;

    final alphaSort =
        widget.sort == TrackSort.title || widget.sort == TrackSort.artist;
    final letterIndex = <String, int>{};
    if (alphaSort) {
      final azRe = RegExp(r'[A-Z]');
      for (var i = 0; i < tracks.length; i++) {
        final field = widget.sort == TrackSort.title
            ? tracks[i].title
            : tracks[i].artist;
        final l = field.isEmpty ? '#' : field[0].toUpperCase();
        letterIndex.putIfAbsent(azRe.hasMatch(l) ? l : '#', () => i);
      }
    }
    _letterIndex = letterIndex;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin contract
    final s = context.read<AppState>();
    _recompute(s);
    final tracks = _tracks;
    final letterIndex = _letterIndex;
    if (tracks.isEmpty) return const _Empty('No tracks');

    final alphaSort =
        widget.sort == TrackSort.title || widget.sort == TrackSort.artist;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('${tracks.length} tracks',
              style: const TextStyle(color: PA.textMuted, fontSize: 12)),
        ),
        Expanded(
          child: Stack(
            children: [
              ListView.builder(
                controller: _scroll,
                itemExtent: _rowHeight,
                padding: EdgeInsets.only(
                    bottom: 8, right: alphaSort ? 22 : 0),
                itemCount: tracks.length,
                itemBuilder: (_, i) => TrackTile(
                    track: tracks[i],
                    onTap: () => s.playTrackInList(tracks, i)),
              ),
              if (alphaSort)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: _AlphabetRail(
                    letters: letterIndex.keys.toList(),
                    active: _railLetter,
                    onLetter: (l) {
                      final idx = letterIndex[l];
                      if (idx == null) return;
                      setState(() => _railLetter = l);
                      _scroll.jumpTo((idx * _rowHeight).clamp(
                          0.0, _scroll.position.maxScrollExtent));
                    },
                    onDone: () => setState(() => _railLetter = null),
                  ),
                ),
              if (_railLetter != null)
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: PA.surfaceElevated.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_railLetter!,
                        style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                            color: PA.accent)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  int Function(Track, Track) _comparator(AppState s) => switch (widget.sort) {
        TrackSort.title => (a, b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        TrackSort.artist => (a, b) =>
            a.artist.toLowerCase().compareTo(b.artist.toLowerCase()),
        TrackSort.album => (a, b) =>
            (a.album ?? '').toLowerCase().compareTo((b.album ?? '').toLowerCase()),
        TrackSort.year => (a, b) => b.year.compareTo(a.year),
        TrackSort.dateAdded => (a, b) => b.dateAdded.compareTo(a.dateAdded),
        TrackSort.duration => (a, b) => b.duration.compareTo(a.duration),
        TrackSort.mostPlayed => (a, b) =>
            s.history.listensOf(b).compareTo(s.history.listensOf(a)),
        TrackSort.firstListen => (a, b) =>
            (s.history.firstListen[a.key] ?? 1 << 62)
                .compareTo(s.history.firstListen[b.key] ?? 1 << 62),
      };
}

/// Compact letter strip: drag or tap to jump the list to that letter.
class _AlphabetRail extends StatelessWidget {
  final List<String> letters;
  final String? active;
  final void Function(String) onLetter;
  final VoidCallback onDone;
  const _AlphabetRail(
      {required this.letters,
      required this.active,
      required this.onLetter,
      required this.onDone});

  static const _all = [
    '#', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'
  ];

  @override
  Widget build(BuildContext context) {
    final have = letters.toSet();
    return LayoutBuilder(
      builder: (_, c) {
        final rowH = c.maxHeight / _all.length;
        void hit(double dy) {
          final i = (dy / rowH).floor().clamp(0, _all.length - 1);
          final l = _all[i];
          if (have.contains(l)) onLetter(l);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (d) => hit(d.localPosition.dy),
          onVerticalDragUpdate: (d) => hit(d.localPosition.dy),
          onVerticalDragEnd: (_) => onDone(),
          onTapDown: (d) => hit(d.localPosition.dy),
          onTapUp: (_) => onDone(),
          child: SizedBox(
            width: 22,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final l in _all)
                  Text(l,
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: l == active
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: !have.contains(l)
                              ? PA.textMuted.withValues(alpha: 0.35)
                              : l == active
                                  ? PA.accent
                                  : PA.textSecondary)),
              ],
            ),
          ),
        );
      },
    );
  }
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
      bottomNavigationBar: const SelectionBar(),
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

// ── Genres ────────────────────────────────────────────────────────────────────

class _GenresView extends StatelessWidget {
  final LocalLibrary lib;
  final String query;
  const _GenresView({required this.lib, required this.query});

  @override
  Widget build(BuildContext context) {
    final byGenre = <String, List<Track>>{};
    for (final t in lib.albums.expand((a) => a.tracks)) {
      final g = (t.genre == null || t.genre!.trim().isEmpty)
          ? 'Unknown genre'
          : t.genre!.trim();
      byGenre.putIfAbsent(g, () => []).add(t);
    }
    var names = byGenre.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (query.isNotEmpty) {
      names = names.where((n) => n.toLowerCase().contains(query)).toList();
    }
    if (names.isEmpty) {
      return const _Empty(
          'No genres — genre tags need Android 11+ to be indexed');
    }
    return ListView.builder(
      itemCount: names.length,
      itemBuilder: (_, i) {
        final name = names[i];
        final tracks = byGenre[name]!;
        return ListTile(
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: PA.card,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.piano, color: PA.textSecondary, size: 22),
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
      bottomNavigationBar: const SelectionBar(),
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
