import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../bridge.dart';
import '../models.dart';
import 'client.dart';
import 'download_service.dart';
import 'models.dart';

/// YouTube tab — search, browse, stream, and download.
class YouTubeTab extends StatefulWidget {
  const YouTubeTab({super.key});

  @override
  State<YouTubeTab> createState() => _YouTubeTabState();
}

class _YouTubeTabState extends State<YouTubeTab>
    with AutomaticKeepAliveClientMixin {
  final _searchCtrl = TextEditingController();
  final _yt = YouTubeService();
  late final _downloadSvc = YouTubeDownloadService(_yt);

  List<YouTubeVideo> _results = [];
  bool _loading = false;
  String? _error;
  String _filter = ''; // '', 'video', 'playlist', 'channel'

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _downloadSvc.dispose();
    _yt.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await _yt.searchVideos(q);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _playNow(YouTubeVideo video) {
    final bridge = context.read<Bridge>();
    bridge.getYoutubeStreamUrl(video.videoId).then((url) {
      if (url != null) {
        final track = Track(
          path: url,
          title: video.title,
          artist: video.author,
          album: 'YouTube',
          source: 'youtube',
          remoteUrl: url,
        );
        context.read<PlayerService>().playTrack(track);
      }
    });
  }

  void _download(YouTubeVideo video) {
    final bridge = context.read<Bridge>();
    // Route to PC bridge download if connected
    if (bridge.isConnected) {
      bridge.youtubeDownload(video.videoId, video.title);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloading "${video.title}" to PC...')),
      );
    } else {
      // Download to device
      _downloadSvc.download(video.videoId, video.title).listen(
        (progress) {
          if (progress >= 1.0) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Downloaded "${video.title}"')),
            );
          }
        },
        onError: (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Download failed: $e')),
          );
        },
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloading "${video.title}"...')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search YouTube',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _results = []);
                      },
                    )
                  : null,
              filled: true,
              fillColor: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withAlpha(100),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            onChanged: (_) => setState(() {}),
          ),
        ),
        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _chip('All', ''),
              const SizedBox(width: 8),
              _chip('Videos', 'video'),
              const SizedBox(width: 8),
              _chip('Playlists', 'playlist'),
              const SizedBox(width: 8),
              _chip('Channels', 'channel'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Results
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              size: 48, color: Colors.red),
                          const SizedBox(height: 12),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _search,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : _results.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search,
                                  size: 64,
                                  color: Theme.of(context).disabledColor),
                              const SizedBox(height: 12),
                              Text(
                                _searchCtrl.text.isEmpty
                                    ? 'Search YouTube'
                                    : 'No results found',
                                style: TextStyle(
                                    color: Theme.of(context).disabledColor),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (context, i) {
                            final video = _results[i];
                            return _VideoTile(
                              video: video,
                              onTap: () => _playNow(video),
                              onDownload: () => _download(video),
                            );
                          },
                        ),
        ),
      ],
    );
  }

  Widget _chip(String label, String value) {
    final selected = _filter == value;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() => _filter = value);
        _search();
      },
      selectedColor: Theme.of(context).colorScheme.primary.withAlpha(40),
      checkmarkColor: Theme.of(context).colorScheme.primary,
    );
  }
}

class _VideoTile extends StatelessWidget {
  final YouTubeVideo video;
  final VoidCallback onTap;
  final VoidCallback onDownload;

  const _VideoTile({
    required this.video,
    required this.onTap,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            Image.network(
              video.thumbnailUrl,
              width: 120,
              height: 68,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 120,
                height: 68,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.broken_image),
              ),
            ),
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  video.durationFormatted,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ),
      ),
      title: Text(
        video.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        '${video.author} • ${_formatViews(video.viewCount)} views',
        style: TextStyle(
            fontSize: 12, color: Theme.of(context).disabledColor),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.download, size: 20),
        onPressed: onDownload,
      ),
      onTap: onTap,
    );
  }

  String _formatViews(int views) {
    if (views >= 1000000) return '${(views / 1000000).toStringAsFixed(1)}M';
    if (views >= 1000) return '${(views / 1000).toStringAsFixed(1)}K';
    return views.toString();
  }
}

// Re-export
export 'client.dart' show YouTubeService;
export 'download_service.dart' show YouTubeDownloadService;
