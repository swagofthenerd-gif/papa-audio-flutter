import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../main.dart' show Shell;
import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';

enum _Source { soulseek, youtube }

/// Search across the bridge's two acquisition paths: Soulseek (downloads run
/// on the PC) and YouTube (stream now, or download to the PC library).
class SearchTab extends StatefulWidget {
  const SearchTab({super.key});
  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final _ctrl = TextEditingController();
  _Source _source = _Source.soulseek;
  bool _busy = false;
  List<SlskFolder> _slskResults = [];
  List<YtResult> _ytResults = [];
  String? _error;

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _slskResults = [];
      _ytResults = [];
    });
    try {
      final bridge = context.read<AppState>().bridge;
      if (_source == _Source.soulseek) {
        final r = await bridge.slskSearch(q);
        if (mounted) setState(() => _slskResults = r);
      } else {
        final r = await bridge.ytSearch(q);
        if (mounted) setState(() => _ytResults = r);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Search failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            controller: _ctrl,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: _source == _Source.soulseek
                  ? 'Search Soulseek…'
                  : 'Search YouTube…',
              filled: true,
              fillColor: PA.card,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward), onPressed: _search),
              border: const OutlineInputBorder(borderSide: BorderSide.none),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: SegmentedButton<_Source>(
            style: SegmentedButton.styleFrom(
              backgroundColor: PA.card,
              foregroundColor: PA.textSecondary,
              selectedBackgroundColor: PA.accent,
              selectedForegroundColor: Colors.black,
              side: BorderSide.none,
            ),
            segments: const [
              ButtonSegment(
                  value: _Source.soulseek,
                  label: Text('Soulseek'),
                  icon: Icon(Icons.folder_shared_outlined)),
              ButtonSegment(
                  value: _Source.youtube,
                  label: Text('YouTube'),
                  icon: Icon(Icons.smart_display_outlined)),
            ],
            selected: {_source},
            onSelectionChanged: (s) => setState(() => _source = s.first),
          ),
        ),
        if (_busy)
          const LinearProgressIndicator(
              color: PA.accent, backgroundColor: PA.card),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_error!,
                style: const TextStyle(color: PA.textSecondary, fontSize: 12)),
          ),
        Expanded(
          child: _source == _Source.soulseek
              ? _SlskResults(results: _slskResults)
              : _YtResults(results: _ytResults),
        ),
      ],
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

class _YtResults extends StatelessWidget {
  final List<YtResult> results;
  const _YtResults({required this.results});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (_, i) {
        final v = results[i];
        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(4),
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
                  content: Text('Download started on PC — it will appear in Home')));
            },
          ),
        );
      },
    );
  }
}
