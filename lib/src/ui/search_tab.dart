import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../local_library.dart';
import '../models.dart';
import '../text_norm.dart';
import '../theme.dart';
import '../yt/yt_models.dart';
import 'download_search_screen.dart';
import 'home_tab.dart' show RecoShelfView;
import 'library_tab.dart' show LocalAlbumScreen, TrackListScreen;
import 'track_tile.dart';
import 'widgets.dart';
import 'yt_browse_screen.dart';
import 'yt_library_screen.dart';
import '../yt/yt_login_screen.dart';
import 'yt_shelf_row.dart';

/// Explore + Search. Empty box = discovery (personalized on-device shelves,
/// then YouTube). Typing = one unified, organized search across your own
/// library and YouTube Music — Top result, your library, songs, albums,
/// artists. Acquisition (Soulseek / PC-YouTube download) lives behind its own
/// entry so it doesn't clutter everyday search.
class SearchTab extends StatefulWidget {
  const SearchTab({super.key});
  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final _ctrl = TextEditingController();
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final q = v.trim();
      if (q != _query) setState(() => _query = q);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  textInputAction: TextInputAction.search,
                  onChanged: _onChanged,
                  onSubmitted: (v) => setState(() => _query = v.trim()),
                  decoration: InputDecoration(
                    hintText: 'Search songs, albums, artists…',
                    filled: true,
                    fillColor: PA.card,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _ctrl.clear();
                              setState(() => _query = '');
                            }),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(PA.rLg),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.cloud_download_outlined),
                tooltip: 'Find music to download',
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const DownloadSearchScreen())),
              ),
              IconButton(
                icon: const Icon(Icons.library_music_outlined),
                tooltip: 'Your YouTube library',
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const YtLibraryScreen())),
              ),
            ],
          ),
        ),
        Expanded(
          child: _query.isEmpty
              ? const _ExploreBrowse()
              : _UnifiedResults(query: _query),
        ),
      ],
    );
  }
}

// ── Unified search results ────────────────────────────────────────────────────

/// The organized result set: your own matches plus YouTube, bucketed by type.
class _Results {
  final List<Track> localSongs;
  final List<LocalAlbum> localAlbums;
  final List<YtMusicItem> ytSongs;
  final List<YtMusicItem> ytAlbums;
  final List<YtMusicItem> ytArtists;
  const _Results({
    this.localSongs = const [],
    this.localAlbums = const [],
    this.ytSongs = const [],
    this.ytAlbums = const [],
    this.ytArtists = const [],
  });

  bool get isEmpty =>
      localSongs.isEmpty &&
      localAlbums.isEmpty &&
      ytSongs.isEmpty &&
      ytAlbums.isEmpty &&
      ytArtists.isEmpty;
}

class _UnifiedResults extends StatefulWidget {
  final String query;
  const _UnifiedResults({required this.query});
  @override
  State<_UnifiedResults> createState() => _UnifiedResultsState();
}

/// Media-type filter for the unified search results.
enum _ResultFilter { all, songs, albums, artists }

class _UnifiedResultsState extends State<_UnifiedResults> {
  bool _busy = false;
  String? _error;
  _Results _r = const _Results();
  _ResultFilter _filter = _ResultFilter.all;

  bool _show(_ResultFilter f) => _filter == _ResultFilter.all || _filter == f;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void didUpdateWidget(covariant _UnifiedResults old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _run();
  }

  /// Local matches are instant (in-memory); YouTube is awaited. We paint the
  /// local results immediately, then fold in YouTube when it lands.
  Future<void> _run() async {
    final s = context.read<AppState>();
    final q = normText(widget.query);

    // Local: songs across library + downloads, plus matching albums.
    final localSongs = <Track>[];
    final seen = <String>{};
    for (final a in s.localLibrary.albums) {
      for (final t in a.tracks) {
        if (s.localLibrary.matchesNorm(t, q) && seen.add(t.key)) {
          localSongs.add(t);
        }
      }
    }
    for (final t in s.downloads.downloaded) {
      if (blobMatches(normText('${t.title} ${t.artist} ${t.album ?? ''}'), q) &&
          seen.add(t.key)) {
        localSongs.add(t);
      }
    }
    final localAlbums = [
      for (final a in s.localLibrary.albums)
        if (blobMatches(normText('${a.name} ${a.artist}'), q)) a
    ];

    setState(() {
      _busy = true;
      _error = null;
      _r = _Results(localSongs: localSongs, localAlbums: localAlbums);
    });

    try {
      final shelves = await s.yt.tube.search(widget.query);
      if (!mounted) return;
      final ytSongs = <YtMusicItem>[];
      final ytAlbums = <YtMusicItem>[];
      final ytArtists = <YtMusicItem>[];
      final ytSeen = <String>{};
      for (final shelf in shelves) {
        for (final it in shelf.items) {
          final key = it.videoId ?? it.browseId ?? it.playlistId ?? it.title;
          if (!ytSeen.add(key)) continue;
          switch (it.kind) {
            case YtItemKind.song:
            case YtItemKind.video:
              ytSongs.add(it);
            case YtItemKind.album:
              ytAlbums.add(it);
            case YtItemKind.artist:
            case YtItemKind.channel:
              ytArtists.add(it);
            case YtItemKind.playlist:
              break; // playlists are noise in a music search
          }
        }
      }
      setState(() {
        _r = _Results(
          localSongs: localSongs,
          localAlbums: localAlbums,
          ytSongs: ytSongs,
          ytAlbums: ytAlbums,
          ytArtists: ytArtists,
        );
        _busy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'YouTube search failed: $e';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final r = _r;
    final showSongs = _show(_ResultFilter.songs);
    final showAlbums = _show(_ResultFilter.albums);
    final showArtists = _show(_ResultFilter.artists);
    return Column(
      children: [
        if (_busy)
          const LinearProgressIndicator(
              color: PA.accent, backgroundColor: PA.card),
        if (!r.isEmpty) _filterChips(),
        Expanded(
          child: (r.isEmpty && !_busy)
              ? _EmptyResults(query: widget.query, error: _error)
              : ListView(
                  padding: const EdgeInsets.only(bottom: 90),
                  children: [
                    // Top result — the single strongest hit. Only in "All".
                    if (_filter == _ResultFilter.all && _topResult() != null)
                      _topResult()!,

                    if (showSongs &&
                        (r.localSongs.isNotEmpty || r.localAlbums.isNotEmpty))
                      const _SectionHeader('From your library'),
                    if (showSongs) ...[
                      for (final t in r.localSongs.take(4))
                        TrackTile(
                          track: t,
                          onTap: () => s.playTrackInList(
                              r.localSongs, r.localSongs.indexOf(t)),
                        ),
                      if (r.localSongs.length > 4)
                        _MoreButton(
                          label:
                              'All ${r.localSongs.length} songs in your library',
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => TrackListScreen(
                                      title:
                                          '“${widget.query}” in your library',
                                      tracks: r.localSongs))),
                        ),
                    ],
                    if (showAlbums && r.localAlbums.isNotEmpty)
                      _AlbumRow(
                        albums: r.localAlbums,
                        onTap: (a) => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => LocalAlbumScreen(album: a))),
                      ),

                    if (showSongs && r.ytSongs.isNotEmpty)
                      const _SectionHeader('Songs'),
                    if (showSongs)
                      for (final it in r.ytSongs.take(8))
                        _YtSongTile(item: it),

                    if (showAlbums && r.ytAlbums.isNotEmpty) ...[
                      const _SectionHeader('Albums'),
                      _YtCardRow(items: r.ytAlbums),
                    ],
                    if (showArtists && r.ytArtists.isNotEmpty) ...[
                      const _SectionHeader('Artists'),
                      _YtCardRow(items: r.ytArtists),
                    ],
                    if (_error != null && r.ytSongs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_error!,
                            style: const TextStyle(
                                color: PA.textMuted, fontSize: 12)),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  /// Media-type filter chips above the results (All / Songs / Albums /
  /// Artists) — Namida-style result narrowing.
  Widget _filterChips() {
    const labels = {
      _ResultFilter.all: 'All',
      _ResultFilter.songs: 'Songs',
      _ResultFilter.albums: 'Albums',
      _ResultFilter.artists: 'Artists',
    };
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final f in _ResultFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(labels[f]!),
                selected: _filter == f,
                showCheckmark: false,
                selectedColor: PA.accent,
                backgroundColor: PA.card,
                labelStyle: TextStyle(
                    color: _filter == f ? Colors.black : PA.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
                side: BorderSide.none,
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  setState(() => _filter = f);
                },
              ),
            ),
        ],
      ),
    );
  }

  /// Strongest hit rendered as a big card: prefer an exact-name local artist
  /// or album, else the first YouTube result, else the first local song.
  Widget? _topResult() {
    final r = _r;
    final q = normText(widget.query);
    // Exact local album name match makes a great top result.
    for (final a in r.localAlbums) {
      if (normText(a.name) == q) {
        return _TopResultCard(
          title: a.name,
          subtitle: 'Album · ${a.artist}',
          art: TrackArt(
              artUri: 'localart://${a.artTrackId}/${a.albumId}',
              size: 72,
              px: 160),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => LocalAlbumScreen(album: a))),
        );
      }
    }
    if (r.ytArtists.isNotEmpty && normText(r.ytArtists.first.title) == q) {
      return _ytTop(r.ytArtists.first, 'Artist');
    }
    if (r.ytSongs.isNotEmpty) {
      return _ytTop(r.ytSongs.first, 'Song');
    }
    if (r.localSongs.isNotEmpty) {
      final t = r.localSongs.first;
      return _TopResultCard(
        title: t.title,
        subtitle: 'Song · ${t.artist}',
        art: TrackArt(
            artUri: t.artUri, artPath: t.artPath, size: 72, px: 160),
        onTap: () => context.read<AppState>().playTrackInList(r.localSongs, 0),
      );
    }
    return null;
  }

  Widget _ytTop(YtMusicItem it, String kindLabel) {
    final circular = it.kind == YtItemKind.artist;
    // YT subtitles for songs already start with "Song"/"Video"; don't repeat it.
    final sub = it.subtitle;
    final subtitle = sub.isEmpty
        ? kindLabel
        : (sub.toLowerCase().startsWith(kindLabel.toLowerCase())
            ? sub
            : '$kindLabel · $sub');
    return _TopResultCard(
      title: it.title,
      subtitle: subtitle,
      circular: circular,
      art: it.thumbnail != null
          ? NetworkArt(url: it.thumbnail!, slotPx: 72)
          : const ArtPlaceholder(),
      onTap: () => _openYt(context, it),
    );
  }
}

void _openYt(BuildContext context, YtMusicItem it) {
  final s = context.read<AppState>();
  switch (it.kind) {
    case YtItemKind.song:
    case YtItemKind.video:
      s.playYtItem(it);
    case YtItemKind.album:
    case YtItemKind.artist:
    case YtItemKind.channel:
    case YtItemKind.playlist:
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => YtBrowseScreen(item: it)));
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
      );
}

class _TopResultCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget art;
  final bool circular;
  final VoidCallback onTap;
  const _TopResultCard({
    required this.title,
    required this.subtitle,
    required this.art,
    required this.onTap,
    this.circular = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Material(
        color: PA.card,
        borderRadius: BorderRadius.circular(PA.rMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(PA.rMd),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius:
                      BorderRadius.circular(circular ? 36 : PA.rSm),
                  child: SizedBox(width: 72, height: 72, child: art),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: PA.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A YouTube song rendered as a list row (not a carousel card).
class _YtSongTile extends StatelessWidget {
  final YtMusicItem item;
  const _YtSongTile({required this.item});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(PA.rSm),
        child: SizedBox(
          width: 48,
          height: 48,
          child: item.thumbnail != null
              ? NetworkArt(url: item.thumbnail!, slotPx: 48)
              : const ArtPlaceholder(),
        ),
      ),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: item.subtitle.isEmpty
          ? null
          : Text(item.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: PA.textSecondary)),
      onTap: () => context.read<AppState>().playYtItem(item),
    );
  }
}

class _YtCardRow extends StatelessWidget {
  final List<YtMusicItem> items;
  const _YtCardRow({required this.items});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => YtItemCard(item: items[i]),
      ),
    );
  }
}

class _AlbumRow extends StatelessWidget {
  final List<LocalAlbum> albums;
  final void Function(LocalAlbum) onTap;
  const _AlbumRow({required this.albums, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: albums.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final a = albums[i];
          return GestureDetector(
            onTap: () => onTap(a),
            child: SizedBox(
              width: 140,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(PA.rMd),
                    child: TrackArt(
                        artUri: 'localart://${a.artTrackId}/${a.albumId}',
                        size: 140,
                        px: 300),
                  ),
                  const SizedBox(height: 6),
                  Text(a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(a.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: PA.textSecondary, fontSize: 11)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MoreButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _MoreButton({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onTap,
            child: Text(label,
                style: const TextStyle(color: PA.textSecondary)),
          ),
        ),
      );
}

class _EmptyResults extends StatelessWidget {
  final String query;
  final String? error;
  const _EmptyResults({required this.query, this.error});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, color: PA.textMuted, size: 48),
            const SizedBox(height: 12),
            Text('Nothing found for “$query”.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: PA.textSecondary)),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: PA.textMuted, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Explore (default landing) ─────────────────────────────────────────────────

class _ExploreBrowse extends StatefulWidget {
  const _ExploreBrowse();
  @override
  State<_ExploreBrowse> createState() => _ExploreBrowseState();
}

class _ExploreBrowseState extends State<_ExploreBrowse> {
  List<YtShelf> _shelves = const [];
  bool _loading = true;
  String? _error;
  String? _continuation;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tube = context.read<AppState>().yt.tube;
    try {
      final page = await tube.browsePaged('FEmusic_explore');
      var shelves = page.shelves;
      if (shelves.isEmpty) shelves = await tube.home();
      try {
        final nr = await tube.newReleases();
        shelves = [...shelves, ...nr];
      } catch (_) {}
      if (mounted) {
        setState(() {
          _shelves = shelves;
          _continuation = page.continuation;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    final token = _continuation;
    if (token == null || _loadingMore) return;
    _loadingMore = true;
    try {
      final page = await context.read<AppState>().yt.tube.continued(token);
      if (mounted && page.shelves.isNotEmpty) {
        setState(() {
          _shelves = [..._shelves, ...page.shelves];
          _continuation = page.continuation;
        });
      } else {
        _continuation = null;
      }
    } catch (_) {
      // leave continuation so a later scroll can retry
    } finally {
      _loadingMore = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: PA.accent));
    }
    // Rebuild when the on-device recommendation shelves finish computing.
    return AnimatedBuilder(
      animation: Listenable.merge([s.recommendations, s.ytAuth]),
      builder: (context, _) => _buildBody(context, s),
    );
  }

  Widget _buildBody(BuildContext context, AppState s) {
    // Personalized on-device shelves first (your listening), YouTube below.
    // Fire-and-forget refresh (debounced/no-op) so Explore has shelves even
    // if the user never opened Home this session.
    s.recommendations.refresh(s.history, s.localLibrary, s.playlists, s.settings);
    final reco = s.recommendations.shelves;
    return RefreshIndicator(
      color: PA.accent,
      onRefresh: _load,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels > n.metrics.maxScrollExtent - 600 &&
              _continuation != null) {
            _loadMore();
          }
          return false;
        },
        child: CustomScrollView(
          slivers: [
            if (!s.ytAuth.signedIn)
              const SliverToBoxAdapter(child: _SignInBanner()),
            // RecoShelfView returns a sliver already.
            for (final shelf in reco) RecoShelfView(shelf: shelf),
            if (reco.isNotEmpty && _shelves.isNotEmpty)
              const SliverToBoxAdapter(
                  child: _SectionHeader('More on YouTube Music')),
            if (_error != null && _shelves.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Icon(Icons.explore_off,
                          color: PA.textMuted, size: 48),
                      const SizedBox(height: 12),
                      Text('Couldn\'t load YouTube Music.\n$_error',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: PA.textSecondary)),
                      const SizedBox(height: 12),
                      OutlinedButton(
                          onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                ),
              ),
            for (final shelf in _shelves)
              SliverToBoxAdapter(child: YtShelfRow(shelf: shelf)),
            if (_continuation != null)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                      child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: PA.accent))),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _SignInBanner extends StatelessWidget {
  const _SignInBanner();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: PA.card, borderRadius: BorderRadius.circular(PA.rMd)),
      child: Row(
        children: [
          const Icon(Icons.account_circle, color: PA.accent, size: 32),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Sign in to YouTube Music for your personalized mixes '
                'and recommendations.',
                style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: PA.accent, foregroundColor: Colors.black),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const YtLoginScreen())),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
  }
}
