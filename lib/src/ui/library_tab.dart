import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../local_library.dart';
import '../models.dart';
import '../player_service.dart';
import '../text_norm.dart';
import '../theme.dart';
import 'collection_menu.dart';
import 'playlists_ui.dart';
import 'selection_bar.dart';
import 'settings_screen.dart';
import 'track_tile.dart';
import 'widgets.dart';

enum TrackSort { title, artist, album, year, dateAdded, duration, mostPlayed, firstListen, lastListen }

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
  /// a full library re-sort. The query is normalized (case + diacritics).
  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = normText(v));
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final lib = s.localLibrary;
    return AnimatedBuilder(
      animation: Listenable.merge([lib, s.settings]),
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
    return all.where((t) => lib.matchesNorm(t, _query)).toList();
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
              (TrackSort.lastListen, 'Last listen'),
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

// (Track matching now goes through LocalLibrary.matchesNorm — multi-field and
// diacritic-insensitive via precomputed blobs.)

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
        widget.sort == TrackSort.firstListen ||
        widget.sort == TrackSort.lastListen;
    final sig =
        '${widget.query}|${widget.sort.index}|${widget.reverse}|${widget.lib.revision}'
        '${historyBased ? '|${s.history.revision}' : ''}';
    if (sig == _sig) return;
    _sig = sig;

    var tracks = widget.lib.albums.expand((a) => a.tracks).toList();
    if (widget.query.isNotEmpty) {
      tracks =
          tracks.where((t) => widget.lib.matchesNorm(t, widget.query)).toList();
    }
    // Decorate-sort-undecorate for string sorts: lowercase once per track,
    // not twice per comparison. (Perf audit finding.)
    switch (widget.sort) {
      case TrackSort.title:
      case TrackSort.artist:
      case TrackSort.album:
        String keyOf(Track t) => switch (widget.sort) {
              TrackSort.title => t.title.toLowerCase(),
              TrackSort.artist => t.artist.toLowerCase(),
              _ => (t.album ?? '').toLowerCase(),
            };
        final keyed = [for (final t in tracks) (keyOf(t), t)]
          ..sort((a, b) => a.$1.compareTo(b.$1));
        tracks = [for (final k in keyed) k.$2];
      default:
        tracks.sort(_comparator(s));
    }
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
        // Most recently heard first; never-heard tracks sink to the bottom.
        TrackSort.lastListen => (a, b) => (s.history.lastListen[b.key] ?? 0)
            .compareTo(s.history.lastListen[a.key] ?? 0),
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
          .where((a) => blobMatches(normText('${a.name} ${a.artist}'), query))
          .toList();
    }
    if (albums.isEmpty) return const _Empty('No albums');
    final columns = context.read<AppState>().settings.gridColumns;
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
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
      onLongPress: () => showCollectionMenu(context,
          title: album.name, tracks: album.tracks),
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
    // Multi-disc albums get "Disc N" section headers; single-disc albums stay
    // a flat numbered list. Headers are ints, tracks keep their queue index.
    final multiDisc = album.tracks.any((t) => t.discNumber > 1);
    final items = <Object>[];
    int? lastDisc;
    for (var i = 0; i < album.tracks.length; i++) {
      final t = album.tracks[i];
      if (multiDisc && t.discNumber != lastDisc) {
        lastDisc = t.discNumber;
        items.add(t.discNumber);
      }
      items.add((i, t));
    }
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
                  PlayShuffleRow(
                      tracks: album.tracks,
                      collectionId: 'lalbum:${album.albumId}'),
                ],
              ),
            ),
          ),
          SliverList.builder(
            itemCount: items.length,
            itemBuilder: (_, i) {
              final item = items[i];
              if (item is int) {
                // Disc header (only present on multi-disc albums).
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.album, size: 16, color: PA.textMuted),
                      const SizedBox(width: 8),
                      Text('Disc $item',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: PA.textSecondary)),
                    ],
                  ),
                );
              }
              final (idx, t) = item as (int, Track);
              return TrackTile(
                track: t,
                showArt: false,
                leading: SizedBox(
                    width: 24,
                    child: Center(
                        child: Text(
                            '${multiDisc ? t.trackNumber : idx + 1}',
                            style: const TextStyle(color: PA.textMuted)))),
                onTap: () => s.playTrackInList(album.tracks, idx,
                    collectionId: 'lalbum:${album.albumId}'),
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

/// Shared memoization for the grouped views: the (expensive) full-library
/// regroup runs only when the library, splitter settings, or query change —
/// never on incidental rebuilds. (Perf audit finding.)
class _GroupCache {
  Map<String, List<Track>> groups = const {};
  List<String> allNames = const [];
  List<String> names = const [];
  String _groupSig = '';
  String _fullSig = '';

  List<String> update({
    required String groupSig,
    required String query,
    required Map<String, List<Track>> Function() regroup,
  }) {
    if (groupSig != _groupSig) {
      _groupSig = groupSig;
      groups = regroup();
      // Decorate-sort-undecorate: normText once per name, not per comparison.
      final keyed = [for (final n in groups.keys) (normText(n), n)]
        ..sort((a, b) => a.$1.compareTo(b.$1));
      allNames = [for (final k in keyed) k.$2];
      _fullSig = ''; // force query refilter
    }
    final fullSig = '$groupSig|$query';
    if (fullSig != _fullSig) {
      _fullSig = fullSig;
      names = query.isEmpty
          ? allNames
          : [
              for (final n in allNames)
                if (blobMatches(normText(n), query)) n
            ];
    }
    return names;
  }
}

class _ArtistsView extends StatefulWidget {
  final LocalLibrary lib;
  final String query;
  const _ArtistsView({required this.lib, required this.query});
  @override
  State<_ArtistsView> createState() => _ArtistsViewState();
}

class _ArtistsViewState extends State<_ArtistsView> {
  final _cache = _GroupCache();

  @override
  Widget build(BuildContext context) {
    final settings = context.read<AppState>().settings;
    final lib = widget.lib;
    final names = _cache.update(
      groupSig: 'a${lib.revision}|${settings.revision}',
      query: widget.query,
      regroup: () {
        // "A; B feat. C" credits every artist — separators + blacklist are
        // configurable in settings.
        final splitter = settings.artistSplitter;
        final byArtist = <String, List<Track>>{};
        for (final t in lib.albums.expand((a) => a.tracks)) {
          for (final artist in splitter.split(t.artist)) {
            byArtist.putIfAbsent(artist, () => []).add(t);
          }
        }
        return byArtist;
      },
    );
    final byArtist = _cache.groups;
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
                  builder: (_) => TrackListScreen(
                      title: name,
                      tracks: tracks,
                      collectionId: 'artist:$name'))),
          onLongPress: () =>
              showCollectionMenu(context, title: name, tracks: tracks),
        );
      },
    );
  }
}

// ── Genres ────────────────────────────────────────────────────────────────────

class _GenresView extends StatefulWidget {
  final LocalLibrary lib;
  final String query;
  const _GenresView({required this.lib, required this.query});
  @override
  State<_GenresView> createState() => _GenresViewState();
}

class _GenresViewState extends State<_GenresView> {
  final _cache = _GroupCache();

  @override
  Widget build(BuildContext context) {
    final settings = context.read<AppState>().settings;
    final lib = widget.lib;
    final names = _cache.update(
      groupSig: 'g${lib.revision}|${settings.revision}',
      query: widget.query,
      regroup: () {
        final splitter = settings.genreSplitter;
        final byGenre = <String, List<Track>>{};
        for (final t in lib.albums.expand((a) => a.tracks)) {
          final raw = t.genre?.trim() ?? '';
          final genres =
              raw.isEmpty ? const ['Unknown genre'] : splitter.split(raw);
          for (final g in genres) {
            byGenre.putIfAbsent(g, () => []).add(t);
          }
        }
        return byGenre;
      },
    );
    final byGenre = _cache.groups;
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
          // Collage of the genre's album arts, Namida-style.
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: MosaicArt(tracks: tracks, size: 44),
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${tracks.length} tracks',
              style: const TextStyle(color: PA.textMuted, fontSize: 12)),
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => TrackListScreen(
                      title: name,
                      tracks: tracks,
                      collectionId: 'genre:$name'))),
          onLongPress: () =>
              showCollectionMenu(context, title: name, tracks: tracks),
        );
      },
    );
  }
}

// ── Folders ───────────────────────────────────────────────────────────────────

class _FoldersView extends StatefulWidget {
  final LocalLibrary lib;
  final String query;
  const _FoldersView({required this.lib, required this.query});
  @override
  State<_FoldersView> createState() => _FoldersViewState();
}

class _FoldersViewState extends State<_FoldersView> {
  Map<String, List<Track>> _byFolder = const {};
  List<String> _allDirs = const [];
  List<String> _dirs = const [];
  String _sig = '';
  String _fullSig = '';

  void _recompute(LocalLibrary lib, String query) {
    final sig = 'f${lib.revision}';
    if (sig != _sig) {
      _sig = sig;
      final byFolder = <String, List<Track>>{};
      for (final t in lib.albums.expand((a) => a.tracks)) {
        if (t.filePath.isEmpty) continue;
        final sep = t.filePath.contains('/') ? '/' : r'\';
        final idx = t.filePath.lastIndexOf(sep);
        final dir = idx > 0 ? t.filePath.substring(0, idx) : t.filePath;
        byFolder.putIfAbsent(dir, () => []).add(t);
      }
      _byFolder = byFolder;
      _allDirs = byFolder.keys.toList()..sort(_numericAwareCompare);
      _fullSig = '';
    }
    final fullSig = '$sig|$query';
    if (fullSig != _fullSig) {
      _fullSig = fullSig;
      _dirs = query.isEmpty
          ? _allDirs
          : [
              for (final d in _allDirs)
                if (blobMatches(normText(d), query)) d
            ];
    }
  }

  @override
  Widget build(BuildContext context) {
    _recompute(widget.lib, widget.query);
    final byFolder = _byFolder;
    final dirs = _dirs;
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
                  builder: (_) => TrackListScreen(
                      title: name,
                      tracks: tracks,
                      collectionId: 'folder:$dir'))),
          onLongPress: () =>
              showCollectionMenu(context, title: name, tracks: tracks),
        );
      },
    );
  }

  /// "Music 2" sorts before "Music 12" — compares digit runs numerically.
  static final _numRunRe = RegExp(r'(\d+)|(\D+)'); // hoisted: not per-compare
  static int _numericAwareCompare(String a, String b) {
    final ra = _numRunRe;
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
/// The app-bar search icon reveals an inline filter over this list only.
class TrackListScreen extends StatefulWidget {
  final String title;
  final List<Track> tracks;
  final String? collectionId; // enables per-collection resume
  const TrackListScreen(
      {super.key, required this.title, required this.tracks, this.collectionId});

  @override
  State<TrackListScreen> createState() => _TrackListScreenState();
}

class _TrackListScreenState extends State<TrackListScreen> {
  bool _searching = false;
  String _query = '';
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final tracks = _query.isEmpty
        ? widget.tracks
        : [
            for (final t in widget.tracks)
              if (blobMatches(
                  normText('${t.title} ${t.artist} ${t.album ?? ''}'), _query))
                t
          ];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: PA.background,
        title: _searching
            ? TextField(
                autofocus: true,
                style: const TextStyle(fontSize: 15),
                decoration: const InputDecoration(
                    hintText: 'Filter this list…', border: InputBorder.none),
                onChanged: (v) => setState(() => _query = normText(v)),
              )
            : Text(widget.title, style: const TextStyle(fontSize: 17)),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search, size: 20),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _query = '';
            }),
          ),
        ],
      ),
      bottomNavigationBar: const SelectionBar(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: PlayShuffleRow(
                tracks: tracks, collectionId: widget.collectionId),
          ),
          Expanded(
            child: JumpToTrackPill(
              scroll: _scroll,
              tracks: tracks,
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: tracks.length,
                itemBuilder: (_, i) => TrackTile(
                    track: tracks[i],
                    onTap: () => s.playTrackInList(tracks, i,
                        collectionId: widget.collectionId)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Namida-style floating pill: appears while scrolling a long track list and
/// jumps to the now-playing track. Its icon reflects whether that track is
/// above or below the current viewport (or a disc when already in view).
/// Assumes a uniform ~64px row height (TrackTile).
class JumpToTrackPill extends StatefulWidget {
  final ScrollController scroll;
  final List<Track> tracks;
  final Widget child;
  const JumpToTrackPill(
      {super.key,
      required this.scroll,
      required this.tracks,
      required this.child});

  @override
  State<JumpToTrackPill> createState() => _JumpToTrackPillState();
}

class _JumpToTrackPillState extends State<JumpToTrackPill> {
  static const _rowH = 64.0;
  bool _visible = false;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    widget.scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _hide?.cancel();
    widget.scroll.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!_visible) setState(() => _visible = true);
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  int _currentRow(AppState s) {
    final cur = s.playerService.currentTrack;
    if (cur == null) return -1;
    return widget.tracks.indexWhere((t) => t.key == cur.key);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return Stack(
      children: [
        widget.child,
        Positioned(
          right: 12,
          bottom: 16,
          child: AnimatedScale(
            scale: _visible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            child: AnimatedBuilder(
              animation: s.playerService.queueRevision,
              builder: (_, _) {
                final row = _currentRow(s);
                if (row < 0) return const SizedBox.shrink();
                IconData icon = Icons.album;
                if (widget.scroll.hasClients) {
                  final target = row * _rowH;
                  final off = widget.scroll.offset;
                  if (target < off - _rowH) icon = Icons.keyboard_arrow_up;
                  else if (target > off + _rowH * 4) {
                    icon = Icons.keyboard_arrow_down;
                  }
                }
                return Material(
                  color: PA.accent,
                  shape: const StadiumBorder(),
                  elevation: 4,
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.scroll.animateTo(
                        (row * _rowH)
                            .clamp(0.0, widget.scroll.position.maxScrollExtent),
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(icon, size: 18, color: Colors.black),
                        const SizedBox(width: 4),
                        const Text('Playing',
                            style: TextStyle(
                                color: Colors.black,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class PlayShuffleRow extends StatelessWidget {
  final List<Track> tracks;

  /// When set, the collection remembers its listening position and offers a
  /// Resume button here.
  final String? collectionId;
  const PlayShuffleRow({super.key, required this.tracks, this.collectionId});

  @override
  Widget build(BuildContext context) {
    final ps = context.read<AppState>().playerService;
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: PA.accent),
          onPressed: tracks.isEmpty
              ? null
              : () => ps.playQueue(tracks, 0, collectionId: collectionId),
          icon: const Icon(Icons.play_arrow, color: Colors.black),
          label: const Text('Play',
              style:
                  TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
              foregroundColor: PA.accent,
              side: const BorderSide(color: PA.accent)),
          onPressed: tracks.isEmpty ? null : () => ps.playShuffled(tracks),
          icon: const Icon(Icons.shuffle, size: 18),
          label: const Text('Shuffle'),
        ),
        if (collectionId != null && tracks.isNotEmpty)
          FutureBuilder<ResumePoint?>(
            future: ps.resumeFor(collectionId!),
            builder: (_, snap) {
              final r = snap.data;
              if (r == null ||
                  r.index < 0 ||
                  r.index >= tracks.length ||
                  (r.index == 0 && r.positionMs < 15000)) {
                return const SizedBox.shrink();
              }
              return OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: PA.textSecondary,
                    side: const BorderSide(color: PA.separator)),
                onPressed: () => ps.playQueue(tracks, r.index,
                    collectionId: collectionId,
                    startPosition: Duration(milliseconds: r.positionMs)),
                icon: const Icon(Icons.history, size: 16),
                label: Text(
                    'Resume ${r.trackTitle ?? 'track ${r.index + 1}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12)),
              );
            },
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
