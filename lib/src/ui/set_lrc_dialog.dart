import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../lyrics.dart';
import '../models.dart';
import '../theme.dart';

/// LRC editor: view and fetch synced lyrics for a track.
void showLrcEditor(BuildContext context, Track track) {
  final app = context.read<AppState>();
  final lyrics = app.lyrics;
  if (lyrics == null) return;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: PA.surfaceElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _LrcEditorSheet(track: track, lyrics: lyrics),
  );
}

class _LrcEditorSheet extends StatefulWidget {
  final Track track;
  final LyricsService lyrics;
  const _LrcEditorSheet({required this.track, required this.lyrics});

  @override
  State<_LrcEditorSheet> createState() => _LrcEditorSheetState();
}

class _LrcEditorSheetState extends State<_LrcEditorSheet> {
  String _syncedText = '';
  String _plainText = '';
  bool _loading = true;
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await widget.lyrics.forTrack(widget.track);
    if (mounted) {
      setState(() {
        _syncedText = result?.synced.map((l) {
          final d = l.at;
          return '[${d.inMinutes.toString().padLeft(2, '0')}:'
              '${(d.inSeconds % 60).toString().padLeft(2, '0')}.'
              '${(d.inMilliseconds % 1000 ~/ 10).toString().padLeft(2, '0')}]${l.text}';
        }).join('\n') ?? '';
        _plainText = result?.plain ?? '';
        _loading = false;
      });
    }
  }

  Future<void> _fetchOnline() async {
    setState(() => _fetching = true);
    // Re-invoke forTrack — if it was cached as null, remove the cache entry
    // so it retries. The simplest approach: delete and re-fetch.
    try {
      await widget.lyrics.db.db.delete('lyrics',
          where: 'track_key = ?', whereArgs: [widget.track.key]);
    } catch (_) {}
    final result = await widget.lyrics.forTrack(widget.track);
    if (mounted) {
      setState(() {
        _syncedText = result?.synced.map((l) {
          final d = l.at;
          return '[${d.inMinutes.toString().padLeft(2, '0')}:'
              '${(d.inSeconds % 60).toString().padLeft(2, '0')}.'
              '${(d.inMilliseconds % 1000 ~/ 10).toString().padLeft(2, '0')}]${l.text}';
        }).join('\n') ?? '';
        _plainText = result?.plain ?? '';
        _fetching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
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
                const Text('Lyrics',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: PA.text)),
                const Spacer(),
                if (_fetching)
                  const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: PA.accent))
                else
                  TextButton.icon(
                    onPressed: _fetchOnline,
                    icon: const Icon(Icons.refresh, size: 14, color: PA.accent),
                    label: const Text('Re-fetch', style: TextStyle(color: PA.accent)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Expanded(
                child: Center(child: CircularProgressIndicator(color: PA.accent)),
              )
            else if (_syncedText.isEmpty && _plainText.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lyrics, size: 40, color: PA.textMuted),
                      const SizedBox(height: 8),
                      const Text('No lyrics found',
                          style: TextStyle(color: PA.textMuted)),
                      const SizedBox(height: 4),
                      const Text('Tap Re-fetch to search online',
                          style: TextStyle(color: PA.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_syncedText.isNotEmpty) ...[
                      const Text('Synced (LRC)',
                          style: TextStyle(color: PA.accent, fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Expanded(
                        flex: _plainText.isNotEmpty ? 3 : 5,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: PA.card,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SingleChildScrollView(
                            controller: scroll,
                            child: Text(_syncedText,
                                style: const TextStyle(color: PA.text, fontSize: 12,
                                    fontFamily: 'monospace', height: 1.5)),
                          ),
                        ),
                      ),
                    ],
                    if (_plainText.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('Plain',
                          style: TextStyle(color: PA.accent, fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Expanded(
                        flex: _syncedText.isNotEmpty ? 2 : 5,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: PA.card,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SingleChildScrollView(
                            child: Text(_plainText,
                                style: const TextStyle(color: PA.text, fontSize: 13, height: 1.5)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
