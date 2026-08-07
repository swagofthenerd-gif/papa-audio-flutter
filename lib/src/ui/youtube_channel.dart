import 'package:flutter/material.dart';
import 'theme.dart';

/// YouTube channel browser with videos list.
class YoutubeChannelPage extends StatefulWidget {
  final String channelId;
  final String channelName;
  final String? thumbnailUrl;
  const YoutubeChannelPage({super.key, required this.channelId, required this.channelName, this.thumbnailUrl});
  @override
  State<YoutubeChannelPage> createState() => _YoutubeChannelPageState();
}

class _YoutubeChannelPageState extends State<YoutubeChannelPage> with TickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _subscribed = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: 200,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            title: Text(widget.channelName),
            background: Stack(fit: StackFit.expand, children: [
              Container(color: PapaColors.accent.withOpacity(0.3)),
              if (widget.thumbnailUrl != null)
                Image.network(widget.thumbnailUrl!, fit: BoxFit.cover, opacity: const AlwaysStoppedAnimation(0.4)),
            ]),
          ),
          actions: [
            IconButton(
              icon: Icon(_subscribed ? Icons.notifications_active : Icons.notifications_none, color: Colors.white),
              onPressed: () => setState(() => _subscribed = !_subscribed),
              tooltip: _subscribed ? 'Subscribed' : 'Subscribe',
            ),
          ],
          bottom: TabBar(
            controller: _tabCtrl,
            indicatorColor: PapaColors.accent,
            tabs: const [
              Tab(text: 'Videos'),
              Tab(text: 'Playlists'),
              Tab(text: 'About'),
            ],
          ),
        ),
        SliverFillRemaining(
          child: TabBarView(controller: _tabCtrl, children: [
            _videosTab(),
            _playlistsTab(),
            _aboutTab(),
          ]),
        ),
      ]),
    );
  }

  Widget _videosTab() => ListView.builder(
    itemCount: 10,
    itemBuilder: (ctx, i) => Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: Container(width: 100, height: 56, decoration: BoxDecoration(
          color: PapaColors.surface, borderRadius: BorderRadius.circular(6)),
          child: const Icon(Icons.play_circle_outline, color: PapaColors.textMuted)),
        title: Text('Video ${i + 1}', maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: const Text('1.2K views • 2 days ago', style: TextStyle(fontSize: 12)),
      ),
    ),
  );

  Widget _playlistsTab() => const Center(
    child: Text('Playlists coming soon', style: TextStyle(color: PapaColors.textMuted)));

  Widget _aboutTab() => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.channelName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      const Text('Channel description and statistics would appear here.',
        style: TextStyle(color: PapaColors.textSecondary)),
      const SizedBox(height: 16),
      _statRow('Subscribers', '12.5K'),
      _statRow('Videos', '142'),
      _statRow('Joined', 'Jan 2023'),
    ]),
  );

  Widget _statRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      SizedBox(width: 140, child: Text(label, style: const TextStyle(color: PapaColors.textSecondary))),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    ]),
  );
}
