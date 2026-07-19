import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../yt/yt_models.dart';
import 'dialogs.dart';
import 'music_hub.dart';
import 'widgets.dart';
import 'yt_shelf_row.dart';

/// Resolves an artist name to their real YouTube Music channel and shows the
/// full artist page (top songs, albums, singles, "fans might also like"). Falls
/// back to the local/PC hub when the artist isn't on YouTube or search fails
/// (offline, no bridge). Uses pushReplacement so Back skips this loader.
class YtArtistLoader extends StatefulWidget {
  final String name;
  const YtArtistLoader({super.key, required this.name});
  @override
  State<YtArtistLoader> createState() => _YtArtistLoaderState();
}

class _YtArtistLoaderState extends State<YtArtistLoader> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final s = context.read<AppState>();
    try {
      final artist = await s.yt.tube.findArtist(widget.name);
      if (!mounted) return;
      if (artist != null) {
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => YtBrowseScreen(item: artist)));
      } else {
        _fallbackToLocal(s);
      }
    } catch (_) {
      if (mounted) _fallbackToLocal(s);
    }
  }

  void _fallbackToLocal(AppState s) {
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) =>
                MusicHubScreen(query: widget.name, title: widget.name)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PA.background,
      appBar: AppBar(
        backgroundColor: PA.background,
        title: Text(widget.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17)),
      ),
      body: _error == null
          ? const Center(child: CircularProgressIndicator(color: PA.accent))
          : ErrorView(
              message: _error!,
              onRetry: () {
                setState(() => _error = null);
                _resolve();
              }),
    );
  }
}

/// A YT Music entity page: album, artist/channel, or playlist. Shows the
/// header, a Play/Shuffle bar for its tracks, then any sub-shelves (an artist's
/// albums, singles, "fans also like", etc.).
class YtBrowseScreen extends StatefulWidget {
  final YtMusicItem item;
  const YtBrowseScreen({super.key, required this.item});
  @override
  State<YtBrowseScreen> createState() => _YtBrowseScreenState();
}

class _YtBrowseScreenState extends State<YtBrowseScreen> {
  List<YtShelf> _shelves = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Track> _tracks = const []; // memoized once at load
  List<YtMusicItem> _relatedAlbums = const []; // "More from artist" (albums)
  String _relatedArtist = '';

  Future<void> _load() async {
    final tube = context.read<AppState>().yt.tube;
    try {
      final item = widget.item;
      final shelves = item.playlistId != null
          ? await tube.playlist(item.playlistId!)
          : item.browseId != null
              ? await tube.browsePage(item.browseId!)
              : const <YtShelf>[];
      if (!mounted) return;
      setState(() {
        _shelves = shelves;
        _tracks = _extractTracks(shelves);
        _loading = false;
      });
      // For album pages, surface "More from <artist>" — YT album browse
      // usually omits related albums, so fetch the artist's other albums.
      // The album's subtitle often lacks the artist ("Album · 2026"), so take
      // the artist from the album's actual tracks instead.
      if (item.kind == YtItemKind.album && _tracks.isNotEmpty) {
        final artist = _tracks.first.artist;
        if (artist.isNotEmpty && artist != 'YouTube') {
          _loadRelatedAlbums(tube, item, artist);
        }
      }
    } catch (e) {
      if (mounted) setState(() {
            _error = e.toString();
            _loading = false;
          });
    }
  }

  Future<void> _loadRelatedAlbums(
      dynamic tube, YtMusicItem album, String artist) async {
    try {
      final shelves = await tube.search(artist, filter: 'albums');
      final out = <YtMusicItem>[];
      final seen = <String>{album.browseId ?? ''};
      for (final s in (shelves as List)) {
        for (final it in (s.items as List)) {
          final m = it as YtMusicItem;
          if (m.kind == YtItemKind.album &&
              m.browseId != null &&
              seen.add(m.browseId!)) {
            out.add(m);
          }
        }
      }
      if (mounted && out.isNotEmpty) {
        setState(() {
          _relatedAlbums = out.take(20).toList();
          _relatedArtist = artist;
        });
      }
    } catch (_) {
      // best-effort — no related shelf on failure
    }
  }

  /// Direct playable tracks that live on this page (a playlist's/album's songs).
  static List<Track> _extractTracks(List<YtShelf> shelves) {
    final out = <Track>[];
    final seen = <String>{};
    for (final s in shelves) {
      for (final i in s.items) {
        final t = i.toTrack();
        if (t != null && seen.add(t.id)) out.add(t);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final tracks = _tracks;
    return Scaffold(
      backgroundColor: PA.background,
      appBar: AppBar(
        backgroundColor: PA.background,
        title: Text(widget.item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17)),
        actions: [
          if (tracks.isNotEmpty &&
              widget.item.kind != YtItemKind.artist)
            IconButton(
              icon: const Icon(Icons.library_add_outlined),
              tooltip: 'Save to your library',
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final pl = await s.importYtPlaylist(widget.item);
                messenger.showSnackBar(SnackBar(
                    content: Text(pl == null
                        ? 'Nothing to import'
                        : 'Saved "${pl.name}" to your playlists')));
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: PA.accent))
          : _error != null
              ? ErrorView(message: _error!, onRetry: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _load();
                })
              // Lazy: only the header/shelves plus the visible track rows are
              // ever built, so a 200-track playlist opened 10 levels deep costs
              // the same as a short one.
              : CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _header(context, s, tracks)),
                    for (final shelf in _shelves)
                      if (shelf.items.any((i) => i.videoId == null))
                        SliverToBoxAdapter(child: YtShelfRow(shelf: shelf)),
                    SliverList.builder(
                      itemCount: tracks.length,
                      itemBuilder: (_, i) => _trackTile(s, tracks, i),
                    ),
                    if (_relatedAlbums.isNotEmpty)
                      SliverToBoxAdapter(
                        child: YtShelfRow(
                            shelf: YtShelf(
                                title: 'More from $_relatedArtist',
                                items: _relatedAlbums)),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
    );
  }

  Widget _header(BuildContext context, AppState s, List<Track> tracks) {
    return Column(
      children: [
        if (widget.item.thumbnail != null)
          Padding(
            padding: const EdgeInsets.all(20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                  widget.item.kind == YtItemKind.artist ? 100 : PA.rMd),
              child: SizedBox(
                width: 200,
                height: 200,
                child: NetworkArt(url: widget.item.thumbnail!, slotPx: 200),
              ),
            ),
          ),
        if (tracks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: PA.accent,
                        foregroundColor: Colors.black),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play'),
                    onPressed: () => s.playerService.playQueue(tracks, 0),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.shuffle),
                    label: const Text('Shuffle'),
                    onPressed: () => s.playerService.playShuffled(tracks),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _trackTile(AppState s, List<Track> tracks, int i) => ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(PA.rSm),
          child: SizedBox(
            width: 48,
            height: 48,
            child: tracks[i].artUri != null
                ? NetworkArt(url: tracks[i].artUri!, slotPx: 48)
                : const ArtPlaceholder(),
          ),
        ),
        title: Text(tracks[i].title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(tracks[i].artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: PA.textSecondary)),
        onTap: () => s.playerService.playQueue(tracks, i),
        onLongPress: () => showTrackMenu(context, tracks[i]),
      );
}
