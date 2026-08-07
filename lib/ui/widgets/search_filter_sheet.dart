import 'package:flutter/material.dart';

import '../../src/models.dart';
import '../../src/theme.dart';

/// Real-time filtering bottom sheet: type into the text field, pick a filter
/// mode (title / artist / album), and the list updates instantly.
///
/// Returns the filtered [List<Track>] when the user taps a track or closes.
class SearchFilterSheet extends StatefulWidget {
  final List<Track> tracks;

  const SearchFilterSheet({super.key, required this.tracks});

  @override
  State<SearchFilterSheet> createState() => _SearchFilterSheetState();
}

enum _FilterField { title, artist, album }

class _SearchFilterSheetState extends State<SearchFilterSheet> {
  final _ctrl = TextEditingController();
  _FilterField _field = _FilterField.title;
  String _query = '';

  List<Track> get _filtered {
    if (_query.isEmpty) return widget.tracks;
    final q = _query.toLowerCase().trim();
    return [
      for (final t in widget.tracks)
        if (_matches(t, q)) t
    ];
  }

  bool _matches(Track t, String q) => switch (_field) {
        _FilterField.title => t.title.toLowerCase().contains(q),
        _FilterField.artist => t.artist.toLowerCase().contains(q),
        _FilterField.album => (t.album ?? '').toLowerCase().contains(q),
      };

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = _filtered;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                    color: PA.textMuted, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            // Search field
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                style: const TextStyle(fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Search ${_field.name}…',
                  hintStyle: const TextStyle(fontSize: 14),
                  filled: true,
                  fillColor: PA.card,
                  isDense: true,
                  prefixIcon:
                      const Icon(Icons.search, size: 18, color: PA.textMuted),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon:
                              const Icon(Icons.close, size: 16, color: PA.textMuted),
                          onPressed: () {
                            _ctrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            // Filter chips
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                children: [
                  for (final f in _FilterField.values) ...[
                    _Chip(
                      label: f.name[0].toUpperCase() + f.name.substring(1),
                      selected: _field == f,
                      onTap: () => setState(() => _field = f),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            // Results
            Flexible(
              child: results.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('No matches',
                          style: TextStyle(color: PA.textMuted)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount:
                          results.length > 50 ? 50 : results.length,
                      itemBuilder: (_, i) => ListTile(
                        dense: true,
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: SizedBox(
                            width: 42,
                            height: 42,
                            child: results[i].artUri != null
                                ? Image.network(results[i].artUri!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        _noteIcon())
                                : _noteIcon(),
                          ),
                        ),
                        title: Text(results[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14)),
                        subtitle: Text(
                            '${results[i].artist}${results[i].album != null ? ' · ${results[i].album}' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: PA.textSecondary, fontSize: 11)),
                        onTap: () => Navigator.pop(context, results[i]),
                      ),
                    ),
            ),
            if (_filtered.length > 50)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text('Showing 50 of ${_filtered.length} results',
                    style:
                        const TextStyle(color: PA.textMuted, fontSize: 11)),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _noteIcon() => Container(
      color: PA.surfaceElevated,
      child:
          const Icon(Icons.music_note, color: PA.textMuted, size: 22));
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? PA.accent : PA.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? PA.accent : PA.separator, width: 0.5),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? Colors.black : PA.textSecondary)),
      ),
    );
  }
}
