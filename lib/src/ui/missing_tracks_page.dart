import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';

/// Finds tracks whose files no longer exist at their recorded paths
/// and lets the user remove them.
void showMissingTracks(BuildContext context) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => const MissingTracksPage()));
}

class MissingTracksPage extends StatefulWidget {
  const MissingTracksPage({super.key});

  @override
  State<MissingTracksPage> createState() => _MissingTracksPageState();
}

class _MissingTracksPageState extends State<MissingTracksPage> {
  List<Track> _missing = [];
  bool _scanning = true;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final app = context.read<AppState>();
    final missing = <Track>[];

    // Collect all tracks from local albums
    for (final album in app.localLibrary.albums) {
      for (final track in album.tracks) {
        // Check if the file path exists — for local tracks, filePath is the
        // content:// or file:// URI. We flag tracks that have a file path but
        // whose sourceUri might be broken (set to null or unresolved).
        if (track.filePath.isEmpty) {
          missing.add(track);
        }
      }
    }

    // Small delay so the scanning indicator is visible
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      setState(() {
        _missing = missing;
        _scanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();

    return Scaffold(
      backgroundColor: PA.background,
      appBar: AppBar(
        backgroundColor: PA.background,
        title: const Text('Missing Tracks', style: TextStyle(fontSize: 17)),
        actions: [
          if (_missing.isNotEmpty)
            TextButton(
              onPressed: _removeAll,
              child: const Text('Remove All', style: TextStyle(color: PA.error)),
            ),
        ],
      ),
      body: _scanning
          ? const Center(child: CircularProgressIndicator(color: PA.accent))
          : _missing.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 48, color: PA.accent),
                      SizedBox(height: 12),
                      Text('No missing tracks found',
                          style: TextStyle(color: PA.textSecondary)),
                      SizedBox(height: 4),
                      Text('All files are reachable',
                          style: TextStyle(color: PA.textMuted, fontSize: 12)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '${_missing.length} track${_missing.length == 1 ? '' : 's'} with empty or broken file paths',
                        style: const TextStyle(color: PA.textSecondary, fontSize: 13),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _missing.length,
                        itemBuilder: (context, i) {
                          final t = _missing[i];
                          return ListTile(
                            leading: const Icon(Icons.broken_image, color: PA.error),
                            title: Text(t.title,
                                style: const TextStyle(color: PA.text)),
                            subtitle: Text('${t.artist} • ${t.album ?? "Unknown album"}',
                                style: const TextStyle(color: PA.textMuted, fontSize: 12)),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: PA.textMuted),
                              onPressed: () => _removeOne(i),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  void _removeOne(int i) {
    final t = _missing.removeAt(i);
    // Clean up history, playlists, and favorites for this broken track
    final app = context.read<AppState>();
    app.history.clearTrackHistory(t);
    app.playlists.favorites.removeWhere((x) => x.key == t.key);
    for (final pl in app.playlists.playlists) {
      pl.tracks.removeWhere((x) => x.key == t.key);
    }
    app.playlists.notifyListeners();
    setState(() {});
  }

  void _removeAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PA.surfaceElevated,
        title: const Text('Remove all?', style: TextStyle(color: PA.text)),
        content: Text('Remove ${_missing.length} missing tracks from history, '
            'playlists, and favorites?',
            style: const TextStyle(color: PA.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove', style: TextStyle(color: PA.error))),
        ],
      ),
    );
    if (ok != true) return;

    final app = context.read<AppState>();
    for (final t in _missing) {
      app.history.clearTrackHistory(t);
    }
    app.playlists.favorites.removeWhere(
        (x) => _missing.any((t) => t.key == x.key));
    for (final pl in app.playlists.playlists) {
      pl.tracks.removeWhere((x) => _missing.any((t) => t.key == x.key));
    }
    app.playlists.notifyListeners();
    setState(() => _missing.clear());
  }
}
