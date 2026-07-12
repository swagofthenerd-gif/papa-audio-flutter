import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'library_tab.dart';
import 'selection_bar.dart';
import 'track_tile.dart';

/// Everything on the phone by date added, newest first, under age-group
/// headers (Today / Yesterday / This week / This month / Earlier).
class RecentlyAddedScreen extends StatelessWidget {
  const RecentlyAddedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final tracks = [
      for (final a in s.localLibrary.albums) ...a.tracks
    ]..sort((a, b) => b.dateAdded.compareTo(a.dateAdded));

    // Flatten into headers + tracks for a lazy builder.
    final items = <Object>[];
    String? lastGroup;
    for (final t in tracks) {
      final g = _ageGroup(t.dateAdded);
      if (g != lastGroup) {
        lastGroup = g;
        items.add(g);
      }
      items.add(t);
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: PA.background,
        title: const Text('Recently added', style: TextStyle(fontSize: 17)),
      ),
      bottomNavigationBar: const SelectionBar(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: PlayShuffleRow(tracks: tracks, collectionId: 'recent-added'),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final item = items[i];
                if (item is String) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                    child: Text(item,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: PA.textSecondary)),
                  );
                }
                final t = item as Track;
                final idx = tracks.indexOf(t);
                return TrackTile(
                  track: t,
                  subtitleOverride: '${t.artist} · ${_ageLabel(t.dateAdded)}',
                  onTap: () => s.playTrackInList(tracks, idx,
                      collectionId: 'recent-added'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _ageGroup(int epochSec) {
    final days = _daysAgo(epochSec);
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days <= 7) return 'This week';
    if (days <= 30) return 'This month';
    return 'Earlier';
  }

  static String _ageLabel(int epochSec) {
    final days = _daysAgo(epochSec);
    if (days <= 0) return 'today';
    if (days == 1) return 'yesterday';
    if (days <= 30) return '${days}d ago';
    if (days <= 365) return '${(days / 30).floor()}mo ago';
    return '${(days / 365).floor()}y ago';
  }

  static int _daysAgo(int epochSec) {
    if (epochSec <= 0) return 9999;
    final added = DateTime.fromMillisecondsSinceEpoch(epochSec * 1000);
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .difference(DateTime(added.year, added.month, added.day))
        .inDays;
  }
}
