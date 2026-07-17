import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../yt/yt_models.dart';
import 'widgets.dart';
import 'yt_shelf_row.dart';

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

  Future<void> _load() async {
    final tube = context.read<AppState>().yt.tube;
    try {
      final item = widget.item;
      final shelves = item.playlistId != null
          ? await tube.playlist(item.playlistId!)
          : item.browseId != null
              ? await tube.browsePage(item.browseId!)
              : const <YtShelf>[];
      if (mounted) setState(() {
            _shelves = shelves;
            _loading = false;
          });
    } catch (e) {
      if (mounted) setState(() {
            _error = e.toString();
            _loading = false;
          });
    }
  }

  /// Direct playable tracks that live on this page (a playlist's/album's songs).
  List<Track> get _tracks {
    final out = <Track>[];
    final seen = <String>{};
    for (final s in _shelves) {
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
              : ListView(
                  children: [
                    if (widget.item.thumbnail != null)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                                widget.item.kind == YtItemKind.artist ? 100 : PA.rMd),
                            child: SizedBox(
                              width: 200,
                              height: 200,
                              child: NetworkArt(url: widget.item.thumbnail!),
                            ),
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
                                onPressed: () =>
                                    s.playerService.playQueue(tracks, 0),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.shuffle),
                                label: const Text('Shuffle'),
                                onPressed: () =>
                                    s.playerService.playShuffled(tracks),
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Sub-shelves that aren't a plain track list (artist albums,
                    // related artists…) render as their own carousels.
                    for (final shelf in _shelves)
                      if (shelf.items.any((i) => i.videoId == null))
                        YtShelfRow(shelf: shelf),
                    // Track list.
                    for (var i = 0; i < tracks.length; i++)
                      ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(PA.rSm),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: tracks[i].artUri != null
                                ? NetworkArt(url: tracks[i].artUri!)
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
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }
}
