import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../main.dart' show Shell;
import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../yt/yt_models.dart';
import 'widgets.dart';
import 'yt_library_screen.dart';
import '../yt/yt_login_screen.dart';
import 'yt_shelf_row.dart';

/// Explore: music discovery (YouTube Music) plus the acquisition search paths.
/// Browsing (mixes, charts, moods, your feed) is the default landing; a search
/// box switches to results across YT Music, Soulseek, and PC YouTube.
class SearchTab extends StatefulWidget {
  const SearchTab({super.key});
  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (v) => setState(() => _query = v.trim()),
                  decoration: InputDecoration(
                    hintText: 'Search songs, albums, artists…',
                    filled: true,
                    fillColor: PA.card,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _ctrl.clear();
                              setState(() => _query = '');
                            }),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(PA.rLg),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.library_music_outlined),
                tooltip: 'Your YouTube library',
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const YtLibraryScreen())),
              ),
            ],
          ),
        ),
        Expanded(
          child: _query.isEmpty
              ? const _ExploreBrowse()
              : _SearchResults(query: _query),
        ),
      ],
    );
  }
}

// ── Browse (default landing) ──────────────────────────────────────────────────

class _ExploreBrowse extends StatefulWidget {
  const _ExploreBrowse();
  @override
  State<_ExploreBrowse> createState() => _ExploreBrowseState();
}

class _ExploreBrowseState extends State<_ExploreBrowse> {
  List<YtShelf> _shelves = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tube = context.read<AppState>().yt.tube;
    try {
      // Explore surface first (charts, new releases, moods); fall back to home.
      var shelves = await tube.explore();
      if (shelves.isEmpty) shelves = await tube.home();
      if (mounted) setState(() {
            _shelves = shelves;
            _loading = false;
          });
    } catch (e) {
      if (mounted) setState(() {
            _error = e.toString();
            _loading = false;
          });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: PA.accent));
    }
    return RefreshIndicator(
      color: PA.accent,
      onRefresh: _load,
      child: ListView(
        children: [
          if (!s.ytAuth.signedIn) const _SignInBanner(),
          if (_error != null && _shelves.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.explore_off, color: PA.textMuted, size: 48),
                  const SizedBox(height: 12),
                  Text('Couldn\'t load YouTube Music.\n$_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: PA.textSecondary)),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            ),
          for (final shelf in _shelves) YtShelfRow(shelf: shelf),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SignInBanner extends StatelessWidget {
  const _SignInBanner();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: PA.card, borderRadius: BorderRadius.circular(PA.rMd)),
      child: Row(
        children: [
          const Icon(Icons.account_circle, color: PA.accent, size: 32),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Sign in to YouTube Music for your personalized mixes '
                'and recommendations.',
                style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: PA.accent, foregroundColor: Colors.black),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const YtLoginScreen())),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
  }
}

// ── Search results ────────────────────────────────────────────────────────────

class _SearchResults extends StatefulWidget {
  final String query;
  const _SearchResults({required this.query});
  @override
  State<_SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends State<_SearchResults> {
  int _source = 0; // 0 YT Music, 1 Soulseek, 2 PC YouTube
  bool _busy = false;
  String? _error;
  List<YtShelf> _yt = const [];
  List<SlskFolder> _slsk = const [];
  List<YtResult> _pcYt = const [];

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void didUpdateWidget(covariant _SearchResults old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _run();
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final s = context.read<AppState>();
    try {
      if (_source == 0) {
        final r = await s.yt.tube.search(widget.query);
        if (mounted) setState(() => _yt = r);
      } else if (_source == 1) {
        final r = await s.bridge.slskSearch(widget.query);
        if (mounted) setState(() => _slsk = r);
      } else {
        final r = await s.bridge.ytSearch(widget.query);
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
    return Column(
      children: [
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
              ButtonSegment(value: 0, label: Text('YT Music')),
              ButtonSegment(value: 1, label: Text('Soulseek')),
              ButtonSegment(value: 2, label: Text('PC YouTube')),
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
                style: const TextStyle(color: PA.textSecondary, fontSize: 12)),
          ),
        Expanded(child: _results()),
      ],
    );
  }

  Widget _results() {
    if (_source == 1) return _SlskResults(results: _slsk);
    if (_source == 2) return _PcYtResults(results: _pcYt);
    // YT Music: flatten shelves (songs first) into a scrollable list of cards.
    return ListView(
      children: [for (final shelf in _yt) YtShelfRow(shelf: shelf)],
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
                  content: Text('Download started on PC — it will appear in Home')));
            },
          ),
        );
      },
    );
  }
}
