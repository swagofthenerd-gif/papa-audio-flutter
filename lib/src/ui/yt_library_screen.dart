import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';
import '../yt/innertube.dart';
import '../yt/yt_models.dart';
import 'widgets.dart';
import 'yt_login_screen.dart';
import 'yt_shelf_row.dart';

/// The signed-in user's YouTube Music library: playlists, subscriptions, liked
/// songs, and watch history — each a lazily-loaded, paginating surface.
class YtLibraryScreen extends StatelessWidget {
  const YtLibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    if (!s.ytAuth.signedIn) {
      return Scaffold(
        backgroundColor: PA.background,
        appBar: AppBar(
            backgroundColor: PA.background,
            title: const Text('Your YouTube', style: TextStyle(fontSize: 17))),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_circle_outlined,
                  color: PA.textMuted, size: 56),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text('Sign in to see your playlists, subscriptions, '
                    'liked songs and history.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: PA.textSecondary)),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: PA.accent, foregroundColor: Colors.black),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const YtLoginScreen())),
                child: const Text('Sign in'),
              ),
            ],
          ),
        ),
      );
    }
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: PA.background,
        appBar: AppBar(
          backgroundColor: PA.background,
          title: const Text('Your YouTube', style: TextStyle(fontSize: 17)),
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: PA.accent,
            labelColor: PA.text,
            unselectedLabelColor: PA.textSecondary,
            tabs: [
              Tab(text: 'Playlists'),
              Tab(text: 'Artists'),
              Tab(text: 'Liked'),
              Tab(text: 'History'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _LibrarySurface(load: (t) => t.libraryPlaylists()),
            _LibrarySurface(load: (t) => t.libraryArtists()),
            _LibrarySurface(load: (t) => t.likedSongs()),
            _LibrarySurface(load: (t) => t.history()),
          ],
        ),
      ),
    );
  }
}

class _LibrarySurface extends StatefulWidget {
  final Future<List<YtShelf>> Function(Innertube) load;
  const _LibrarySurface({required this.load});
  @override
  State<_LibrarySurface> createState() => _LibrarySurfaceState();
}

class _LibrarySurfaceState extends State<_LibrarySurface>
    with AutomaticKeepAliveClientMixin {
  List<YtShelf> _shelves = const [];
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true; // don't refetch when switching tabs back

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tube = context.read<AppState>().yt.tube;
    try {
      final shelves = await widget.load(tube);
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
    super.build(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: PA.accent));
    }
    if (_error != null && _shelves.isEmpty) {
      return ErrorView(message: _error!, onRetry: () {
        setState(() {
          _loading = true;
          _error = null;
        });
        _load();
      });
    }
    // Flatten every shelf's items into one scroll grid of cards.
    final items = [for (final s in _shelves) ...s.items];
    if (items.isEmpty) {
      return const Center(
          child: Text('Nothing here yet',
              style: TextStyle(color: PA.textSecondary)));
    }
    return RefreshIndicator(
      color: PA.accent,
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.74,
          crossAxisSpacing: 12,
          mainAxisSpacing: 4,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => YtItemCard(item: items[i], size: 160),
      ),
    );
  }
}
