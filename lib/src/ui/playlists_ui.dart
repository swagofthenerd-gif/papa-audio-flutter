import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../history.dart';
import '../models.dart';
import '../playlists.dart';
import '../theme.dart';
import 'dialogs.dart';
import 'library_tab.dart';
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
        // The playlist may have been deleted while this screen is open.
        if (!s.playlists.playlists.any((p) => p.id == playlist.id)) {
          return const Scaffold(body: SizedBox.shrink());
        }
        return Scaffold(
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
                    case 'delete':
                      await s.playlists.delete(playlist);
                      if (context.mounted) Navigator.pop(context);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: PlayShuffleRow(tracks: playlist.tracks),
              ),
              Expanded(
                child: playlist.tracks.isEmpty
                    ? const Center(
                        child: Text('No tracks yet — use “Add to playlist” on any track',
                            style: TextStyle(
                                color: PA.textSecondary, fontSize: 13)))
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: playlist.tracks.length,
                        onReorderItem: (from, to) =>
                            s.playlists.reorder(playlist, from, to),
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
                            onDismissed: (_) =>
                                s.playlists.removeAt(playlist, i),
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
                              onTap: () =>
                                  s.playTrackInList(playlist.tracks, i),
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

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return AnimatedBuilder(
      animation: s.history,
      builder: (context, _) {
        final groups = _grouped(s.history, widget.query);
        if (groups.isEmpty) {
          return const Center(
              child: Text('Nothing played yet',
                  style: TextStyle(color: PA.textSecondary)));
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 80),
          children: [
            for (final day in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                          '${day.key} · ${day.value.length} listens',
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
                          day.value.map((e) => e.track).toList(), 0),
                    ),
                  ],
                ),
              ),
              for (final e in day.value)
                Dismissible(
                  key: ObjectKey(e),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: PA.error,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) => s.history.removeEntry(e),
                  child: TrackTile(
                    track: e.track,
                    swipeActions: false,
                    keySalt: e.at,
                    subtitleOverride:
                        '${e.track.artist} · ${_timeLabel(e.at)}',
                    onTap: () => s.playTrackInList([e.track], 0),
                  ),
                ),
            ],
          ],
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
