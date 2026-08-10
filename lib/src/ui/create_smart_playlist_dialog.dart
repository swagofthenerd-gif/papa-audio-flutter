import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';

/// Smart playlist rule builder with AND/OR groups.
void showSmartPlaylistBuilder(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: PA.surfaceElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const _SmartPlaylistSheet(),
  );
}

class _SmartPlaylistSheet extends StatefulWidget {
  const _SmartPlaylistSheet();

  @override
  State<_SmartPlaylistSheet> createState() => _SmartPlaylistSheetState();
}

class _SmartPlaylistSheetState extends State<_SmartPlaylistSheet> {
  String _name = '';
  final List<_Rule> _rules = [];
  String _operator = 'AND';

  static const _filterTypes = [
    'title contains', 'title equals', 'title starts with',
    'artist contains', 'artist equals',
    'album contains', 'album equals',
    'genre contains', 'genre equals',
    'duration >', 'duration <',
    'year >', 'year <',
    'play count >', 'play count <',
  ];

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scroll) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: PA.textMuted.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Smart Playlist',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: PA.text)),
                const Spacer(),
                TextButton(
                  onPressed: _create,
                  child: const Text('Create', style: TextStyle(color: PA.accent)),
                ),
              ],
            ),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Playlist name',
                hintStyle: TextStyle(color: PA.textMuted),
                filled: true,
                fillColor: PA.card,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              style: const TextStyle(color: PA.text),
              onChanged: (v) => _name = v,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Combine rules with:',
                    style: TextStyle(color: PA.textSecondary, fontSize: 12)),
                const SizedBox(width: 8),
                _opChip('AND'),
                const SizedBox(width: 4),
                _opChip('OR'),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _rules.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.rule, size: 40, color: PA.textMuted),
                          const SizedBox(height: 8),
                          const Text('No rules yet',
                              style: TextStyle(color: PA.textMuted)),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _addRule,
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add rule'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: PA.accent,
                              foregroundColor: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: scroll,
                      itemCount: _rules.length + 1,
                      itemBuilder: (context, i) {
                        if (i == _rules.length) {
                          return TextButton.icon(
                            onPressed: _addRule,
                            icon: const Icon(Icons.add, size: 14, color: PA.accent),
                            label: const Text('Add rule', style: TextStyle(color: PA.accent)),
                          );
                        }
                        return _RuleTile(
                          rule: _rules[i],
                          filterTypes: _filterTypes,
                          onRemove: () => setState(() => _rules.removeAt(i)),
                          onChanged: () => setState(() {}),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _opChip(String op) {
    final selected = _operator == op;
    return GestureDetector(
      onTap: () => setState(() => _operator = op),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? PA.accent : PA.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(op,
            style: TextStyle(
                color: selected ? Colors.black : PA.textSecondary,
                fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _addRule() => setState(() => _rules.add(_Rule()));

  void _create() async {
    if (_name.trim().isEmpty || _rules.isEmpty) return;
    final app = context.read<AppState>();
    // Collect all local tracks from albums
    final allTracks = <Track>[];
    for (final a in app.localLibrary.albums) {
      allTracks.addAll(a.tracks);
    }
    if (allTracks.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No local tracks to filter')));
      }
      return;
    }

    final h = app.history;
    bool testTrack(Track t, _Rule r) {
      final val = r.value.toLowerCase();
      switch (r.filter) {
        case 'title contains': return t.title.toLowerCase().contains(val);
        case 'title equals': return t.title.toLowerCase() == val;
        case 'title starts with': return t.title.toLowerCase().startsWith(val);
        case 'artist contains': return t.artist.toLowerCase().contains(val);
        case 'artist equals': return t.artist.toLowerCase() == val;
        case 'album contains': return (t.album ?? '').toLowerCase().contains(val);
        case 'album equals': return (t.album ?? '').toLowerCase() == val;
        case 'genre contains': return (t.genre ?? '').toLowerCase().contains(val);
        case 'genre equals': return (t.genre ?? '').toLowerCase() == val;
        case 'duration >': return t.duration > (int.tryParse(val) ?? 0);
        case 'duration <': return t.duration < (int.tryParse(val) ?? 999999);
        case 'year >': return t.year > (int.tryParse(val) ?? 0);
        case 'year <': return t.year < (int.tryParse(val) ?? 9999);
        case 'play count >': return h.listensOf(t) > (int.tryParse(val) ?? 0);
        case 'play count <': return h.listensOf(t) < (int.tryParse(val) ?? 999999);
        default: return true;
      }
    }

    final filtered = allTracks.where((t) {
      if (_operator == 'AND') return _rules.every((r) => testTrack(t, r));
      return _rules.any((r) => testTrack(t, r));
    }).toList();

    if (filtered.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No tracks match these rules')));
      }
      return;
    }

    final pl = await app.playlists.create(_name.trim());
    await app.playlists.addTracks(pl, filtered);
    if (mounted) Navigator.pop(context);
  }
}

class _Rule {
  String filter = 'title contains';
  String value = '';
  _Rule();
}

class _RuleTile extends StatelessWidget {
  final _Rule rule;
  final List<String> filterTypes;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _RuleTile({
    required this.rule,
    required this.filterTypes,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              value: rule.filter,
              dropdownColor: PA.surfaceElevated,
              style: const TextStyle(color: PA.text, fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                filled: true,
                fillColor: PA.card,
                border: InputBorder.none,
              ),
              items: filterTypes.map((f) => DropdownMenuItem(
                  value: f, child: Text(f, style: const TextStyle(fontSize: 11)))).toList(),
              onChanged: (v) {
                if (v != null) { rule.filter = v; onChanged(); }
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: TextField(
              style: const TextStyle(color: PA.text, fontSize: 12),
              decoration: const InputDecoration(
                hintText: 'Value',
                hintStyle: TextStyle(color: PA.textMuted, fontSize: 11),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                filled: true,
                fillColor: PA.card,
                border: InputBorder.none,
              ),
              onChanged: (v) { rule.value = v; },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: PA.textMuted),
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}
