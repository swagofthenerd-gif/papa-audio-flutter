import 'package:flutter/material.dart';
import '../models.dart';
import '../player_service.dart';
import '../playlists.dart';
import '../history.dart';
import '../settings.dart';
import '../bridge.dart';
import '../db.dart';
import 'track_tile.dart';
import 'theme.dart';
import 'dialogs.dart';

/// Multi-source enhanced track list with sort, search, multi-select, and shuffle/play header.
/// Used by album, artist, genre, playlist, and search result pages.
class EnhancedTrackList extends StatefulWidget {
  final List<Track> tracks;
  final String? title;
  final String? subtitle;
  final String? artworkUrl;
  final bool showDiscHeaders;
  final bool showArtistLinks;
  final bool reorderable;
  final void Function(int oldIndex, int newIndex)? onReorder;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShuffle;
  final Widget? headerWidget;

  const EnhancedTrackList({
    super.key, required this.tracks, this.title, this.subtitle, this.artworkUrl,
    this.showDiscHeaders = false, this.showArtistLinks = true,
    this.reorderable = false, this.onReorder, this.onPlayAll, this.onShuffle, this.headerWidget,
  });

  @override
  State<EnhancedTrackList> createState() => _EnhancedTrackListState();
}

class _EnhancedTrackListState extends State<EnhancedTrackList> {
  String _query = '';
  SortType _sort = SortType.defaultSort;
  bool _reverse = false;
  final _selected = <String>{};

  List<Track> get _filtered {
    var list = List<Track>.from(widget.tracks);
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((t) =>
        t.title.toLowerCase().contains(q) ||
        t.artist.toLowerCase().contains(q) ||
        t.album.toLowerCase().contains(q)
      ).toList();
    }
    final s = SettingsService();
    switch (_sort) {
      case SortType.title:
        list.sort((a, b) => a.title.compareTo(b.title));
        break;
      case SortType.artist:
        list.sort((a, b) => a.artist.compareTo(b.artist));
        break;
      case SortType.album:
        list.sort((a, b) => a.album.compareTo(b.album));
        break;
      case SortType.duration:
        list.sort((a, b) => a.durationMs.compareTo(b.durationMs));
        break;
      case SortType.plays:
        break; // Would need play counts
      case SortType.dateAdded:
        list.sort((a, b) => b.lastModified.compareTo(a.lastModified));
        break;
      case SortType.year:
        list.sort((a, b) => (a.year ?? 0).compareTo(b.year ?? 0));
        break;
      default:
        break;
    }
    if (_reverse) list = list.reversed.toList();
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _filtered;
    return Column(children: [
      // Header
      if (widget.headerWidget != null) widget.headerWidget!,
      if (widget.title != null || widget.subtitle != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            if (widget.artworkUrl != null) ...[
              ClipRRect(borderRadius: BorderRadius.circular(8),
                child: Image.network(widget.artworkUrl!, width: 56, height: 56, fit: BoxFit.cover)),
              const SizedBox(width: 12),
            ],
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (widget.title != null) Text(widget.title!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              if (widget.subtitle != null) Text(widget.subtitle!, style: const TextStyle(color: PapaColors.textSecondary, fontSize: 13)),
            ])),
            if (widget.onPlayAll != null || widget.onShuffle != null)
              Row(children: [
                if (widget.onShuffle != null)
                  IconButton(icon: const Icon(Icons.shuffle), onPressed: widget.onShuffle),
                if (widget.onPlayAll != null)
                  IconButton(icon: const Icon(Icons.play_circle_fill, color: PapaColors.accent, size: 40), onPressed: widget.onPlayAll),
              ]),
          ]),
        ),
      // Search bar
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: TextField(
          decoration: InputDecoration(
            hintText: 'Filter ${tracks.length} tracks...',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: Icon(Icons.sort, color: _sort != SortType.defaultSort ? PapaColors.accent : null),
                onPressed: _showSortMenu),
            ]),
            filled: true, fillColor: PapaColors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      // Sort chips
      if (_sort != SortType.defaultSort)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(children: [
            _chip(_sort.label, true, () => setState(() { _sort = SortType.defaultSort; })),
            const SizedBox(width: 8),
            _chip(_reverse ? '↓ desc' : '↑ asc', false, () => setState(() => _reverse = !_reverse)),
          ]),
        ),
      // Track list
      Expanded(child: _selected.isNotEmpty
        ? Stack(children: [
            ListView.builder(
              itemCount: tracks.length,
              itemBuilder: (ctx, i) => _trackTile(tracks[i]),
            ),
            Positioned(bottom: 0, left: 0, right: 0,
              child: _selectionBar(tracks)),
          ])
        : widget.reorderable
          ? ReorderableListView.builder(
              itemCount: tracks.length,
              onReorder: widget.onReorder ?? (oldIndex, newIndex) {},
              itemBuilder: (ctx, i) => _trackTile(tracks[i], key: ValueKey('track_${tracks[i].path}')),
            )
          : ListView.builder(
              itemCount: tracks.length,
              itemBuilder: (ctx, i) => _trackTile(tracks[i]),
            ),
      ),
    ]);
  }

  Widget _trackTile(Track t, {Key? key}) {
    final isSelected = _selected.contains(t.path);
    return GestureDetector(
      key: key,
      onLongPress: () => setState(() {
        if (_selected.contains(t.path)) { _selected.remove(t.path); }
        else { _selected.add(t.path); }
        HapticFeedback.selectionClick();
      }),
      onTap: _selected.isNotEmpty
        ? () => setState(() {
            if (_selected.contains(t.path)) { _selected.remove(t.path); }
            else { _selected.add(t.path); }
          })
        : () => PlayerService.inst.playTrack(t),
      child: Container(
        color: isSelected ? PapaColors.accent.withOpacity(0.15) : null,
        child: TrackTile(track: t, showArtist: widget.showArtistLinks,
          trailing: isSelected
            ? Icon(Icons.check_circle, color: PapaColors.accent, size: 22)
            : null),
      ),
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? PapaColors.accent.withOpacity(0.2) : PapaColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: active ? PapaColors.accent : PapaColors.separator),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: active ? PapaColors.accent : PapaColors.textSecondary)),
    ),
  );

  Widget _selectionBar(List<Track> tracks) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: PapaColors.surfaceElevated.withOpacity(0.95),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
    child: SafeArea(top: false, child: Row(children: [
      Text('${_selected.length} selected', style: const TextStyle(fontWeight: FontWeight.w600)),
      const Spacer(),
      _barBtn(Icons.playlist_add, 'Next', () {
        for (final t in tracks.where((t) => _selected.contains(t.path))) {
          PlayerService.inst.addToQueue(t);
        }
        setState(() => _selected.clear());
      }),
      _barBtn(Icons.queue_music, 'Queue', () {
        for (final t in tracks) { PlayerService.inst.addToQueue(t); }
      }),
      _barBtn(Icons.favorite_border, 'Like', () async {
        for (final t in tracks.where((t) => _selected.contains(t.path))) {
          await PlaylistsService.inst.addToFavorites(t);
        }
        setState(() => _selected.clear());
      }),
    ])),
  );

  Widget _barBtn(IconData icon, String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 22, color: PapaColors.textSecondary),
        Text(label, style: const TextStyle(fontSize: 10, color: PapaColors.textSecondary)),
      ]),
    ),
  );

  void _showSortMenu() {
    showModalBottomSheet(context: context, builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final s in SortType.values)
          ListTile(title: Text(s.label), leading: Icon(_sort == s ? Icons.check : null),
            onTap: () { setState(() => _sort = s); Navigator.pop(ctx); }),
        ListTile(title: const Text('Reverse'), leading: Icon(_reverse ? Icons.check : null),
          onTap: () { setState(() => _reverse = !_reverse); Navigator.pop(ctx); }),
      ]),
    ));
  }
}

enum SortType {
  defaultSort('Default'),
  title('Title'),
  artist('Artist'),
  album('Album'),
  duration('Duration'),
  plays('Most Played'),
  dateAdded('Date Added'),
  year('Year');

  final String label;
  const SortType(this.label);
}
