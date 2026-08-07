import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../src/app_state.dart';
import '../../src/models.dart';
import '../../src/theme.dart';

/// A folder-based music browser. Lists directories and audio files using
/// `dart:io`. Tapping a folder navigates into it; tapping ".." goes up;
/// tapping an audio file plays it in the player.
class FolderBrowserScreen extends StatefulWidget {
  /// Starting directory. If null, defaults to `/storage/emulated/0` on Android
  /// or the filesystem root.
  final String? initialPath;

  const FolderBrowserScreen({super.key, this.initialPath});

  @override
  State<FolderBrowserScreen> createState() => _FolderBrowserScreenState();
}

class _FolderBrowserScreenState extends State<FolderBrowserScreen> {
  static const _audioExts = {
    'mp3', 'flac', 'wav', 'm4a', 'ogg', 'opus', 'aac', 'wma',
    'aiff', 'aif', 'ape', 'wv', 'mpc', 'tta', 'dsf', 'dff',
  };

  String _currentPath = '';
  List<FileSystemEntity> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath ?? _defaultRoot();
    _loadDir();
  }

  static String _defaultRoot() {
    if (Platform.isAndroid) {
      // Common Android storage root
      final candidates = [
        '/storage/emulated/0',
        '/sdcard',
        '/storage/emulated/0/Music',
        '/storage/emulated/0/Download',
      ];
      for (final c in candidates) {
        if (Directory(c).existsSync()) return c;
      }
    }
    return Platform.isAndroid ? '/storage/emulated/0' : '/';
  }

  Future<void> _loadDir() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dir = Directory(_currentPath);
      if (!await dir.exists()) {
        setState(() {
          _error = 'Directory does not exist: $_currentPath';
          _loading = false;
        });
        return;
      }
      final all = await dir.list().toList();
      // Separate directories and audio files
      final dirs = <Directory>[];
      final files = <File>[];
      for (final e in all) {
        if (e is Directory) {
          dirs.add(e);
        } else if (e is File) {
          final ext = e.path.split('.').last.toLowerCase();
          if (_audioExts.contains(ext)) {
            files.add(e);
          }
        }
      }
      // Sort: directories first (alphabetical), then files (alphabetical)
      dirs.sort((a, b) =>
          a.path.toLowerCase().compareTo(b.path.toLowerCase()));
      files.sort((a, b) =>
          a.path.toLowerCase().compareTo(b.path.toLowerCase()));

      setState(() {
        _entries = [...dirs, ...files];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _navigateTo(String path) {
    setState(() => _currentPath = path);
    _loadDir();
  }

  void _goUp() {
    // Don't go above root
    final parent = Directory(_currentPath).parent.path;
    if (parent == _currentPath) return;
    _navigateTo(parent);
  }

  void _playFile(File file) {
    final s = context.read<AppState>();
    final fileName = file.path.split(Platform.pathSeparator).last;
    final nameWithoutExt = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;

    // Create a temporary Track object for local playback
    final track = Track(
      id: 'local:${file.path}',
      title: nameWithoutExt,
      artist: 'Unknown Artist',
      filePath: file.path,
      sourceUri: file.uri.toString(),
      album: _currentPath.split(Platform.pathSeparator).last,
    );

    s.playerService.playNext(track);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Playing: $nameWithoutExt',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        duration: const Duration(milliseconds: 1400),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String get _displayPath {
    // Show a friendlier path
    if (Platform.isAndroid) {
      final p = _currentPath;
      if (p.startsWith('/storage/emulated/0')) {
        return 'Internal Storage${p.substring(20)}';
      }
      if (p.startsWith('/sdcard')) {
        return 'SD Card${p.substring(7)}';
      }
    }
    return _currentPath;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: PA.background,
        title: Text(
          _displayPath,
          style: const TextStyle(fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: PA.accent),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_off, color: PA.textMuted, size: 48),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: PA.textSecondary)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_currentPath != _defaultRoot())
                    TextButton.icon(
                      onPressed: _goUp,
                      icon: const Icon(Icons.arrow_upward, size: 18),
                      label: const Text('Go up'),
                    ),
                  const SizedBox(width: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: PA.accent),
                    onPressed: _loadDir,
                    child: const Text('Retry',
                        style: TextStyle(color: Colors.black)),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    if (_entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open, color: PA.textMuted, size: 48),
            const SizedBox(height: 12),
            const Text('No audio files in this folder',
                style: TextStyle(color: PA.textSecondary)),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _goUp,
              icon: const Icon(Icons.arrow_upward, size: 18),
              label: const Text('Go up'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: _entries.length + 1, // +1 for ".." row
      itemBuilder: (_, i) {
        // First row is ".." (parent directory) if not at root
        if (i == 0) {
          final isRoot = Directory(_currentPath).parent.path == _currentPath;
          if (isRoot) {
            // At filesystem root — show a header
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(
                _displayPath,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: PA.textSecondary),
              ),
            );
          }
          return ListTile(
            leading: const Icon(Icons.arrow_upward, color: PA.warning),
            title: const Text('..',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Parent folder',
                style: TextStyle(color: PA.textMuted, fontSize: 12)),
            onTap: _goUp,
          );
        }

        final entry = _entries[i - 1];
        if (entry is Directory) {
          final name = entry.path.split(Platform.pathSeparator).last;
          return ListTile(
            leading: const Icon(Icons.folder, color: PA.warning),
            title: Text(name,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right, color: PA.textMuted),
            onTap: () => _navigateTo(entry.path),
          );
        } else if (entry is File) {
          final name = entry.path.split(Platform.pathSeparator).last;
          return ListTile(
            leading: const Icon(Icons.audio_file, color: PA.accent),
            title: Text(name,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: FutureBuilder<FileStat>(
              future: entry.stat(),
              builder: (_, snap) {
                final size = snap.data?.size;
                if (size == null) return const SizedBox.shrink();
                return Text(_fmtSize(size),
                    style:
                        const TextStyle(color: PA.textMuted, fontSize: 11));
              },
            ),
            trailing: const Icon(Icons.play_arrow, color: PA.accent),
            onTap: () => _playFile(entry),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
