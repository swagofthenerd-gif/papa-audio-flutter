import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'dialogs.dart';

/// Long-press menu for any collection (album, artist, genre, folder,
/// playlist): bulk actions on its whole track list.
void showCollectionMenu(BuildContext context,
    {required String title, required List<Track> tracks}) {
  if (tracks.isEmpty) return;
  final s = context.read<AppState>();
  showModalBottomSheet(
    context: context,
    backgroundColor: PA.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${tracks.length} tracks',
                style: const TextStyle(color: PA.textMuted, fontSize: 12)),
          ),
          const Divider(height: 1, color: PA.separator),
          ListTile(
            dense: true,
            leading: const Icon(Icons.play_arrow, color: PA.accent, size: 22),
            title: const Text('Play', style: TextStyle(fontSize: 14)),
            onTap: () {
              Navigator.pop(sheetCtx);
              s.playerService.playQueue(tracks, 0);
            },
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.shuffle, color: PA.textSecondary, size: 22),
            title: const Text('Shuffle', style: TextStyle(fontSize: 14)),
            onTap: () {
              Navigator.pop(sheetCtx);
              s.playerService.playShuffled(tracks);
            },
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.playlist_play,
                color: PA.textSecondary, size: 22),
            title: const Text('Play next', style: TextStyle(fontSize: 14)),
            onTap: () async {
              Navigator.pop(sheetCtx);
              for (final t in tracks) {
                await s.playerService.playNext(t); // chained: keeps order
              }
            },
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.queue, color: PA.textSecondary, size: 22),
            title: const Text('Add to queue', style: TextStyle(fontSize: 14)),
            onTap: () async {
              Navigator.pop(sheetCtx);
              for (final t in tracks) {
                await s.playerService.addToQueue(t);
              }
            },
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.playlist_add,
                color: PA.textSecondary, size: 22),
            title:
                const Text('Add to playlist…', style: TextStyle(fontSize: 14)),
            onTap: () {
              Navigator.pop(sheetCtx);
              showAddToPlaylistSheet(context, tracks);
            },
          ),
        ],
      ),
    ),
  );
}
