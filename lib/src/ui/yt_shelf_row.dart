import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';
import '../yt/yt_models.dart';
import 'dialogs.dart';
import 'widgets.dart';
import 'yt_browse_screen.dart';

/// Renders one YT Music shelf as a horizontal card row. Shared by the Home
/// YouTube shelves and the Explore surfaces. Card shape adapts to the item
/// kind — circular for artists, square for everything else.
class YtShelfRow extends StatelessWidget {
  final YtShelf shelf;
  const YtShelfRow({super.key, required this.shelf});

  @override
  Widget build(BuildContext context) {
    if (shelf.items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Text(shelf.title,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
        ),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: shelf.items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => YtItemCard(item: shelf.items[i]),
          ),
        ),
      ],
    );
  }
}

/// A single YT Music item card. Tapping plays (songs) or opens the entity
/// (albums/artists/playlists) via [AppState.playYtItem] / a browse screen.
class YtItemCard extends StatelessWidget {
  final YtMusicItem item;
  final double size;
  const YtItemCard({super.key, required this.item, this.size = 150});

  bool get _circular => item.kind == YtItemKind.artist;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return PressScale(
        child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(_circular ? size : PA.rMd),
        onTap: () => _open(context, s),
        onLongPress: item.videoId == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                final t = item.toTrack();
                if (t != null) showTrackMenu(context, t);
              },
        child: SizedBox(
          width: size,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius:
                    BorderRadius.circular(_circular ? size : PA.rMd),
                child: SizedBox(
                  width: size,
                  height: size,
                  child: item.thumbnail != null
                      ? NetworkArt(url: item.thumbnail!, slotPx: size)
                      : const ArtPlaceholder(),
                ),
              ),
              const SizedBox(height: 6),
              Text(item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: _circular ? TextAlign.center : TextAlign.start,
                  style:
                      const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              if (item.subtitle.isNotEmpty)
                Text(item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: _circular ? TextAlign.center : TextAlign.start,
                    style:
                        const TextStyle(color: PA.textSecondary, fontSize: 11)),
            ],
          ),
        ),
      ),
    ));
  }

  void _open(BuildContext context, AppState s) {
    switch (item.kind) {
      case YtItemKind.song:
      case YtItemKind.video:
        s.playYtItem(item);
      case YtItemKind.album:
      case YtItemKind.artist:
      case YtItemKind.channel:
      case YtItemKind.playlist:
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => YtBrowseScreen(item: item)));
    }
  }
}
