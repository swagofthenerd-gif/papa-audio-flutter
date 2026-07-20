import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../main.dart' show Shell;
import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';

/// Acquisition search — finding music to download onto the library, separate
/// from the everyday "what do I want to hear now" search. Two sources:
/// Soulseek (lossless folders) and PC-side YouTube (downloaded to the library).
class DownloadSearchScreen extends StatefulWidget {
  const DownloadSearchScreen({super.key});
  @override
  State<DownloadSearchScreen> createState() => _DownloadSearchScreenState();
}

class _DownloadSearchScreenState extends State<DownloadSearchScreen> {
  final _ctrl = TextEditingController();
  int _source = 0; // 0 Soulseek, 1 PC YouTube
  bool _busy = false;
  String? _error;
  String _query = '';
  List<SlskFolder> _slsk = const [];
  List<YtResult> _pcYt = const [];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_query.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final s = context.read<AppState>();
    try {
      if (_source == 0) {
        final r = await s.bridge.slskSearch(_query);
        if (mounted) setState(() => _slsk = r);
      } else {
        final r = await s.bridge.ytSearch(_query);
        if (mounted) setState(() => _pcYt = r);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Search failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: PA.background,
        title: const Text('Find music to download',
            style: TextStyle(fontSize: 17)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) {
                _query = v.trim();
                _run();
              },
              decoration: InputDecoration(
                hintText: 'Search Soulseek and YouTube…',
                filled: true,
                fillColor: PA.card,
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(PA.rLg),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SegmentedButton<int>(
              style: SegmentedButton.styleFrom(
                backgroundColor: PA.card,
                foregroundColor: PA.textSecondary,
                selectedBackgroundColor: PA.accent,
                selectedForegroundColor: Colors.black,
                side: BorderSide.none,
              ),
              segments: const [
                ButtonSegment(value: 0, label: Text('Soulseek (lossless)')),
                ButtonSegment(value: 1, label: Text('YouTube')),
              ],
              selected: {_source},
              onSelectionChanged: (v) {
                setState(() => _source = v.first);
                _run();
              },
            ),
          ),
          if (_busy)
            const LinearProgressIndicator(
                color: PA.accent, backgroundColor: PA.card),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!,
                  style:
                      const TextStyle(color: PA.textSecondary, fontSize: 12)),
            ),
          Expanded(
            child: _source == 0
                ? _SlskResults(results: _slsk)
                : _PcYtResults(results: _pcYt),
          ),
        ],
      ),
    );
  }
}

class _SlskResults extends StatelessWidget {
  final List<SlskFolder> results;
  const _SlskResults({required this.results});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (_, i) {
        final f = results[i];
        return ListTile(
          title: Text(f.folder.split('\\').last,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              '${f.username} · ${f.fileCount} files'
              '${f.bitrate != null ? ' · ${f.bitrate}kbps' : ''}',
              style: const TextStyle(color: PA.textSecondary)),
          trailing: IconButton(
            icon: const Icon(Icons.download, color: PA.accent),
            onPressed: () {
              context.read<AppState>().bridge.slskDownload(f);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: const Text('Download started on PC'),
                action: SnackBarAction(
                  label: 'VIEW',
                  onPressed: () => Shell.switchTo?.call(3),
                ),
              ));
            },
          ),
        );
      },
    );
  }
}

class _PcYtResults extends StatelessWidget {
  final List<YtResult> results;
  const _PcYtResults({required this.results});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (_, i) {
        final v = results[i];
        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(PA.rSm),
            child: SizedBox(
              width: 56,
              height: 56,
              child: v.thumbnail != null
                  ? CachedNetworkImage(
                      imageUrl: v.thumbnail!,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const ArtPlaceholder())
                  : const ArtPlaceholder(),
            ),
          ),
          title: Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              '${v.channel}'
              '${v.durationSec != null ? ' · ${fmtDuration(v.durationSec!.toDouble())}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: PA.textSecondary)),
          onTap: () => context.read<AppState>().playYt(v),
          trailing: IconButton(
            icon: const Icon(Icons.download, color: PA.accent),
            tooltip: 'Download to PC library',
            onPressed: () {
              context.read<AppState>().bridge.ytDownload(v);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                      'Download started on PC — it will appear in Home')));
            },
          ),
        );
      },
    );
  }
}
