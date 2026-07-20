import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../history.dart';
import '../models.dart';
import '../playlists.dart';
import '../theme.dart';
import 'collection_menu.dart';
import 'dialogs.dart';
import 'library_tab.dart';
import 'selection_bar.dart';
import 'track_tile.dart';
import 'widgets.dart';

// ── Playlists ─────────────────────────────────────────────────────────────────

class PlaylistsView extends StatelessWidget {
  final String query;
  const PlaylistsView({super.key, required this.query});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return AnimatedBuilder(
      animation: s.playlists,
      builder: (context, _) {
        var lists = s.playlists.playlists;
        if (query.isNotEmpty) {
          lists = lists
              .where((p) => p.name.toLowerCase().contains(query))
              .toList();
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 80),
          children: [
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [PA.accent, Color(0xFF0E5A2B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.favorite, color: Colors.white, size: 22),
              ),
              title: const Text('Liked Songs',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${s.playlists.favorites.length} tracks',
                  style: const TextStyle(color: PA.textMuted, fontSize: 12)),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const _FavoritesScreen())),
              onLongPress: () => showCollectionMenu(context,
                  title: 'Liked Songs', tracks: s.playlists.favorites),
            ),
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: PA.card,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.add, color: PA.accent),
              ),
              title: const Text('New playlist'),
              onTap: () async {
                final name =
                    await promptText(context, 'New playlist', 'Name');
                if (name != null) await s.playlists.create(name);
              },
            ),
            const Divider(color: PA.separator, height: 12),
            for (final p in lists)
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: PA.card,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.queue_music,
                      color: PA.textSecondary, size: 22),
                ),
                title:
                    Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${p.tracks.length} tracks · ${fmtDuration(p.totalDuration)}',
                    style: const TextStyle(color: PA.textMuted, fontSize: 12)),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => PlaylistScreen(playlist: p))),
                onLongPress: () => showCollectionMenu(context,
                    title: p.name, tracks: p.tracks),
              ),
          ],
        );
      },
    );
  }
}

class _FavoritesScreen extends StatelessWidget {
  const _FavoritesScreen();
  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return AnimatedBuilder(
      animation: s.playlists,
      builder: (context, _) => TrackListScreen(
          title: 'Liked Songs', tracks: s.playlists.favorites),
    );
  }
}

class PlaylistScreen extends StatelessWidget {
  final Playlist playlist;
  const PlaylistScreen({super.key, required this.playlist});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return AnimatedBuilder(
      animation: s.playlists,
      builder: (context, _) {
        // The playlist may have been deleted while this screen is open — pop
        // back to where the user came from instead of showing a blank screen.
        if (!s.playlists.playlists.any((p) => p.id == playlist.id)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).maybePop();
          });
          return const Scaffold(body: SizedBox.shrink());
        }
        return Scaffold(
          bottomNavigationBar: const SelectionBar(),
          appBar: AppBar(
            backgroundColor: PA.background,
            title: Text(playlist.name, style: const TextStyle(fontSize: 17)),
            actions: [
              PopupMenuButton<String>(
                color: PA.surfaceElevated,
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (v) async {
                  switch (v) {
                    case 'rename':
                      final name = await promptText(
                          context, 'Rename playlist', playlist.name);
                      if (name != null) await s.playlists.rename(playlist, name);
                    case 'dedupe':
                      final n = await s.playlists.removeDuplicates(playlist);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(n == 0
                                ? 'No duplicates found'
                                : 'Removed $n duplicate${n == 1 ? '' : 's'}'),
                            duration: const Duration(milliseconds: 1400)));
                      }
                    case 'delete':
                      await s.playlists.delete(playlist);
                      if (context.mounted) Navigator.pop(context);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(
                      value: 'dedupe', child: Text('Remove duplicates')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              if (playlist.tracks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(fmtCollectionMeta(playlist.tracks),
                        style:
                            const TextStyle(color: PA.textMuted, fontSize: 12)),
                  ),
                ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: PlayShuffleRow(
                    tracks: playlist.tracks,
                    collectionId: 'playlist:${playlist.id}'),
              ),
              Expanded(
                child: playlist.tracks.isEmpty
                    ? const EmptyState(
                        icon: Icons.queue_music_outlined,
                        title: 'No tracks yet',
                        hint: 'Use “Add to playlist” on any track to build it up.')
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: playlist.tracks.length,
                        onReorder: (from, to) {
                          if (to > from) to -= 1; // ReorderableListView convention
                          s.playlists.reorder(playlist, from, to);
                        },
                        itemBuilder: (_, i) {
                          final t = playlist.tracks[i];
                          return Dismissible(
                            key: ValueKey('pl${playlist.id}$i${t.key}'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: PA.error,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child:
                                  const Icon(Icons.delete, color: Colors.white),
                            ),
                            onDismissed: (_) {
                              final removed = t;
                              final at = i;
                              s.playlists.removeAt(playlist, at);
                              ScaffoldMessenger.of(context)
                                ..clearSnackBars()
                                ..showSnackBar(SnackBar(
                                  content: Text('Removed ${removed.title}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  behavior: SnackBarBehavior.floating,
                                  action: SnackBarAction(
                                    label: 'Undo',
                                    onPressed: () => s.playlists
                                        .insertAt(playlist, at, removed),
                                  ),
                                ));
                            },
                            child: TrackTile(
                              track: t,
                              swipeActions: false,
                              keySalt: i,
                              trailingExtra: ReorderableDragStartListener(
                                index: i,
                                child: const Padding(
                                  padding: EdgeInsets.only(right: 6),
                                  child: Icon(Icons.drag_handle,
                                      color: PA.textMuted, size: 18),
                                ),
                              ),
                              onTap: () => s.playTrackInList(
                                  playlist.tracks, i,
                                  collectionId: 'playlist:${playlist.id}'),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Saved queues ──────────────────────────────────────────────────────────────

class QueuesView extends StatelessWidget {
  final String query;
  const QueuesView({super.key, required this.query});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return AnimatedBuilder(
      animation: s.queues,
      builder: (context, _) {
        var queues = s.queues.saved;
        if (query.isNotEmpty) {
          queues = queues
              .where((q) => q.tracks.any((t) =>
                  t.title.toLowerCase().contains(query) ||
                  t.artist.toLowerCase().contains(query)))
              .toList();
        }
        if (queues.isEmpty) {
          return const EmptyState(
              icon: Icons.history_toggle_off_outlined,
              title: 'No saved queues',
              hint: 'Queues you play are archived here automatically.');
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 80),
          itemCount: queues.length,
          itemBuilder: (_, i) {
            final q = queues[i];
            final first = q.tracks.first;
            return Dismissible(
              key: ValueKey('sq${q.at}'),
              direction: DismissDirection.endToStart,
              background: Container(
                color: PA.error,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              onDismissed: (_) {
                s.queues.delete(q);
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(SnackBar(
                    content: const Text('Queue removed'),
                    behavior: SnackBarBehavior.floating,
                    action: SnackBarAction(
                      label: 'Undo',
                      onPressed: () => s.queues.restore(q),
                    ),
                  ));
              },
              child: ListTile(
                leading: TrackArt(
                    artUri: first.artUri,
                    artPath: first.artPath,
                    size: 44,
                    px: 120),
                title: Text(_when(q.at),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: Text(
                    '${q.tracks.length} tracks · ${first.title}'
                    '${q.tracks.length > 1 ? ', …' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: PA.textSecondary, fontSize: 12)),
                trailing: IconButton(
                  icon: const Icon(Icons.play_circle_outline,
                      color: PA.accent, size: 22),
                  onPressed: () => s.playerService.playQueue(q.tracks, 0),
                ),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => TrackListScreen(
                            title: _when(q.at), tracks: q.tracks))),
              ),
            );
          },
        );
      },
    );
  }

  static String _when(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today $h:$m';
    if (diff == 1) return 'Yesterday $h:$m';
    return '${that.day}/${that.month}/${that.year} $h:$m';
  }
}

// ── History ───────────────────────────────────────────────────────────────────

class HistoryView extends StatefulWidget {
  final String query;
  const HistoryView({super.key, required this.query});
  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  // Day-grouping over thousands of entries is memoized by history revision so
  // background listen events never trigger full regroups of a hidden tab.
  Map<String, List<HistoryEntry>> _groups = const {};
  String _sig = '';

  Map<String, List<HistoryEntry>> _grouped(HistoryService h, String query) {
    final sig = '${h.revision}|$query';
    if (sig == _sig) return _groups;
    _sig = sig;
    var entries = h.entries;
    if (query.isNotEmpty) {
      entries = entries
          .where((e) =>
              e.track.title.toLowerCase().contains(query) ||
              e.track.artist.toLowerCase().contains(query))
          .toList();
    }
    final groups = <String, List<HistoryEntry>>{};
    for (final e in entries) {
      groups.putIfAbsent(_dayLabel(e.at), () => []).add(e);
    }
    return _groups = groups;
  }

  /// Flattened day-headers + entries so ListView.builder only constructs
  /// visible rows — 20k history entries must not build 20k widgets.
  /// (Perf audit finding.)
  List<Object> _flat = const [];
  String _flatSig = '';

  List<Object> _flattened(HistoryService h, String query) {
    final sig = '${h.revision}|$query';
    if (sig == _flatSig) return _flat;
    _flatSig = sig;
    final groups = _grouped(h, query);
    final flat = <Object>[];
    groups.forEach((day, entries) {
      flat.add((day, entries));
      flat.addAll(entries);
    });
    return _flat = flat;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return AnimatedBuilder(
      animation: s.history,
      builder: (context, _) {
        final flat = _flattened(s.history, widget.query);
        if (flat.isEmpty) {
          return const Center(
              child: Text('Nothing played yet',
                  style: TextStyle(color: PA.textSecondary)));
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 80),
          itemCount: flat.length,
          itemBuilder: (_, i) {
            final item = flat[i];
            if (item is (String, List<HistoryEntry>)) {
              final (day, entries) = item;
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('$day · ${entries.length} listens',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: PA.textSecondary)),
                    ),
                    IconButton(
                      tooltip: 'Play this day',
                      icon: const Icon(Icons.play_circle_outline,
                          size: 20, color: PA.accent),
                      onPressed: () => s.playTrackInList(
                          entries.map((e) => e.track).toList(), 0),
                    ),
                  ],
                ),
              );
            }
            final e = item as HistoryEntry;
            return Dismissible(
              key: ObjectKey(e),
              direction: DismissDirection.endToStart,
              background: Container(
                color: PA.error,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              onDismissed: (_) {
                s.history.removeEntry(e);
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(SnackBar(
                    content: Text('Removed ${e.track.title} from history',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    duration: const Duration(seconds: 3),
                    action: SnackBarAction(
                      label: 'Undo',
                      textColor: PA.accent,
                      onPressed: () => s.history.restoreEntry(e),
                    ),
                  ));
              },
              child: TrackTile(
                track: e.track,
                swipeActions: false,
                keySalt: e.at,
                subtitleOverride: '${e.track.artist} · ${_timeLabel(e.at)}',
                onTap: () => s.playTrackInList([e.track], 0),
              ),
            );
          },
        );
      },
    );
  }

  static String _dayLabel(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final y = that.year == today.year ? '' : ' ${that.year}';
    return '${that.day} ${months[that.month - 1]}$y';
  }

  static String _timeLabel(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ── Most played ───────────────────────────────────────────────────────────────

enum _Range { all, today, week, month, year }

class MostPlayedView extends StatefulWidget {
  final String query;
  const MostPlayedView({super.key, required this.query});
  @override
  State<MostPlayedView> createState() => _MostPlayedViewState();
}

class _MostPlayedViewState extends State<MostPlayedView> {
  _Range _range = _Range.all;

  // Ranking is memoized by history revision — hidden-tab rebuilds are free.
  List<(Track, int)> _ranked = const [];
  String _sig = '';

  DateTime? get _since {
    final now = DateTime.now();
    return switch (_range) {
      _Range.all => null,
      _Range.today => DateTime(now.year, now.month, now.day),
      _Range.week => now.subtract(const Duration(days: 7)),
      _Range.month => now.subtract(const Duration(days: 30)),
      _Range.year => now.subtract(const Duration(days: 365)),
    };
  }

  List<(Track, int)> _rank(HistoryService h) {
    final sig = '${h.revision}|$_range|${widget.query}';
    if (sig == _sig) return _ranked;
    _sig = sig;
    var ranked = h.mostPlayed(since: _since, limit: 200);
    if (widget.query.isNotEmpty) {
      ranked = ranked
          .where((r) =>
              r.$1.title.toLowerCase().contains(widget.query) ||
              r.$1.artist.toLowerCase().contains(widget.query))
          .toList();
    }
    return _ranked = ranked;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return AnimatedBuilder(
      animation: s.history,
      builder: (context, _) {
        final ranked = _rank(s.history);
        return Column(
          children: [
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final (r, label) in [
                    (_Range.all, 'All time'),
                    (_Range.today, 'Today'),
                    (_Range.week, 'Week'),
                    (_Range.month, 'Month'),
                    (_Range.year, 'Year'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
                      child: ChoiceChip(
                        label: Text(label, style: const TextStyle(fontSize: 12)),
                        selected: _range == r,
                        selectedColor: PA.accent,
                        backgroundColor: PA.card,
                        labelStyle: TextStyle(
                            color: _range == r ? Colors.black : PA.text),
                        onSelected: (_) => setState(() => _range = r),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ranked.isEmpty
                  ? const Center(
                      child: Text('No listens in this range',
                          style: TextStyle(color: PA.textSecondary)))
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: ranked.length,
                      itemBuilder: (_, i) {
                        final (t, n) = ranked[i];
                        return TrackTile(
                          track: t,
                          leading: SizedBox(
                            width: 44,
                            child: Center(
                              child: Text('${i + 1}',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: i < 3 ? PA.accent : PA.textMuted)),
                            ),
                          ),
                          subtitleOverride:
                              '${t.artist} · $n listen${n == 1 ? '' : 's'}',
                          onTap: () => s.playTrackInList(
                              ranked.map((r) => r.$1).toList(), i),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
