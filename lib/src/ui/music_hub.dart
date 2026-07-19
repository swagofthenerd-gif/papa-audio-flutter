import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../main.dart' show AlbumScreen, Shell;
import '../app_state.dart';
import '../models.dart';
import '../text_norm.dart';
import '../theme.dart';
import 'library_tab.dart';
import 'selection_bar.dart';
import 'track_tile.dart';
import 'widgets.dart';
import 'yt_browse_screen.dart';

/// Spotify-style "go to artist/album" landing: one scroll with labeled
/// sections in fixed order — YouTube, From your PC, On this phone — each
/// hidden when it has nothing. Reached by tapping the artist or title in the
/// full player, or Go to artist/album in any track menu.
class MusicHubScreen extends StatelessWidget {
  final String query; // search term (artist or album name)
  final String title; // screen title
  const MusicHubScreen({super.key, required this.query, required this.title});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final normQuery = normText(query);

    // On this phone: any track whose blob matches (artist taps also credit
    // split artists because the blob contains the full artist string).
    final localTracks = [
      for (final a in s.localLibrary.albums)
        for (final t in a.tracks)
          if (s.localLibrary.matchesNorm(t, normQuery)) t
    ];

    // From your PC: bridge albums whose name or artist matches.
    final pcAlbums = [
      for (final a in s.albums)
        if (blobMatches(normText('${a.name} ${a.artist}'), normQuery)) a
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: PA.background,
        title: Text(title, style: const TextStyle(fontSize: 17)),
      ),
      bottomNavigationBar: const SelectionBar(),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          if (s.configured) _YtSection(query: query),
          if (pcAlbums.isNotEmpty) ...[
            const _HubHeader('From your PC'),
            SizedBox(
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: pcAlbums.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _PcAlbumCard(album: pcAlbums[i]),
              ),
            ),
          ],
          if (localTracks.isNotEmpty) ...[
            _HubHeader('On this phone · ${localTracks.length}'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: PlayShuffleRow(
                  tracks: localTracks, collectionId: 'hub:$normQuery'),
            ),
            for (var i = 0; i < localTracks.length && i < 25; i++)
              TrackTile(
                track: localTracks[i],
                onTap: () => s.playTrackInList(localTracks, i,
                    collectionId: 'hub:$normQuery'),
              ),
            if (localTracks.length > 25)
              TextButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => TrackListScreen(
                            title: title,
                            tracks: localTracks,
                            collectionId: 'hub:$normQuery'))),
                child: Text('See all ${localTracks.length} tracks',
                    style: const TextStyle(color: PA.textSecondary)),
              ),
          ],
          if (!s.configured && localTracks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                  'Nothing found on this phone. Connect your PC to also '
                  'search YouTube and your PC library.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: PA.textSecondary)),
            ),
        ],
      ),
    );
  }
}

/// Opens the most specific destination for a track's album: the matching
/// local album screen, else the matching PC album screen, else the hub.
/// Routes into the Shell's content navigator so the mini player stays
/// visible — these are called from overlays (player sheet, modal menus)
/// whose own context resolves to the root navigator.
void openAlbum(BuildContext context, AppState s, Track t) {
  final albumName = t.album;
  if (albumName == null || albumName.trim().isEmpty) {
    openArtist(context, s, t);
    return;
  }
  final ctx = Shell.contentContext(context);
  final norm = normText(albumName);
  for (final a in s.localLibrary.albums) {
    if (normText(a.name) == norm) {
      Navigator.push(ctx,
          MaterialPageRoute(builder: (_) => LocalAlbumScreen(album: a)));
      return;
    }
  }
  // PC album screens live in main.dart; route through the hub instead of
  // importing across entrypoints — the hub lists matching PC albums anyway.
  Navigator.push(
      ctx,
      MaterialPageRoute(
          builder: (_) => MusicHubScreen(query: albumName, title: albumName)));
}

void openArtist(BuildContext context, AppState s, Track t) {
  // First split artist is the primary credit.
  final artist = s.settings.artistSplitter.split(t.artist).firstOrNull ?? t.artist;
  openArtistName(context, s, artist);
}

/// Open an artist page by name — used by every "tap the artist" affordance
/// (player, album screens, track menus). Routes through the shell content
/// navigator so deep chains (album → artist → album …) stack under the mini
/// player and the back button walks them.
void openArtistName(BuildContext context, AppState s, String name) {
  final artist = s.settings.artistSplitter.split(name).firstOrNull ?? name;
  if (artist.trim().isEmpty) return;
  // Open the real YouTube Music artist page (top songs, albums, singles,
  // similar artists). Falls back to the local/PC hub inside the loader when
  // the artist isn't on YouTube or we're offline.
  Navigator.push(
      Shell.contentContext(context),
      MaterialPageRoute(builder: (_) => YtArtistLoader(name: artist)));
}

class _HubHeader extends StatelessWidget {
  final String text;
  const _HubHeader(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Text(text,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      );
}

/// YouTube results via the bridge — first section, as requested.
class _YtSection extends StatefulWidget {
  final String query;
  const _YtSection({required this.query});
  @override
  State<_YtSection> createState() => _YtSectionState();
}

class _YtSectionState extends State<_YtSection> {
  late final Future<List<YtResult>> _future =
      context.read<AppState>().bridge.ytSearch(widget.query);

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return FutureBuilder<List<YtResult>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
                child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: PA.accent))),
          );
        }
        final results = snap.data ?? const <YtResult>[];
        if (results.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _HubHeader('YouTube'),
            for (final v in results.take(5))
              ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: v.thumbnail != null
                        ? CachedNetworkImage(
                            imageUrl: v.thumbnail!,
                            fit: BoxFit.cover,
                            memCacheWidth: 168,
                            errorWidget: (_, _, _) => const ArtPlaceholder())
                        : const ArtPlaceholder(),
                  ),
                ),
                title:
                    Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${v.channel}${v.durationSec != null ? ' · ${fmtDuration(v.durationSec!.toDouble())}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: PA.textSecondary)),
                onTap: () => s.playYt(v),
                trailing: IconButton(
                  icon: const Icon(Icons.download, color: PA.accent, size: 20),
                  tooltip: 'Download to PC library',
                  onPressed: () {
                    s.bridge.ytDownload(v);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Download started on PC')));
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

/// PC album card — taps route back through the Home tab's album screen via
/// the shared AlbumCard pattern (kept lightweight here).
class _PcAlbumCard extends StatelessWidget {
  final Album album;
  const _PcAlbumCard({required this.album});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Open the album page (deep dive) — play via its own play button.
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => AlbumScreen(album: album))),
      child: SizedBox(
        width: 132,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: TrackArt(artPath: album.artPath, size: 132, px: 300),
            ),
            const SizedBox(height: 6),
            Text(album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text(album.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: PA.textSecondary, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
