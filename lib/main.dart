import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'src/app_state.dart';
import 'src/models.dart';
import 'src/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Never block first paint on init/network — that caused a white screen on
  // launch whenever a (now unreachable) bridge URL was already saved.
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.shaharyar.papaudio.audio',
      androidNotificationChannelName: 'Papa Audio',
      androidNotificationOngoing: true,
    );
  } catch (_) {
    // Background audio unavailable (e.g. emulator) — still start the app.
  }
  final state = AppState();
  runApp(ChangeNotifierProvider.value(value: state, child: const PapaApp()));
  // Restore the saved bridge + load the library AFTER the UI is up.
  state.restore();
}

class PapaApp extends StatelessWidget {
  const PapaApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Papa Audio',
      debugShowCheckedModeBanner: false,
      theme: papaTheme(),
      home: const Root(),
    );
  }
}

class Root extends StatelessWidget {
  const Root({super.key});
  @override
  Widget build(BuildContext context) {
    final configured = context.select<AppState, bool>((s) => s.configured);
    return configured ? const Shell() : const SetupScreen();
  }
}

// ── Setup ─────────────────────────────────────────────────────────────────────
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  Future<void> _connect() async {
    setState(() => _busy = true);
    final ok = await context.read<AppState>().connect(_ctrl.text);
    if (mounted) setState(() => _busy = false);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.read<AppState>().error ?? 'Failed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.music_note, color: PA.accent, size: 48),
              const SizedBox(height: 12),
              const Text('Papa Audio',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Connect to your PC to stream your library',
                  style: TextStyle(color: PA.textSecondary)),
              const SizedBox(height: 28),
              TextField(
                controller: _ctrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'PC IP address',
                  hintText: '192.168.1.x',
                  filled: true,
                  fillColor: PA.card,
                  border: OutlineInputBorder(borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: PA.accent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _busy ? null : _connect,
                  child: _busy
                      ? const SizedBox(
                          height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Connect',
                          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shell (bottom nav + mini player) ──────────────────────────────────────────
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  final _pages = const [HomeTab(), SearchTab(), LibraryTab()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _pages[_tab]),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          NavigationBar(
            backgroundColor: PA.surface,
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
              NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: 'Library'),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Home: PC library grid ─────────────────────────────────────────────────────
class HomeTab extends StatelessWidget {
  const HomeTab({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (s.loading && s.albums.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: PA.accent));
    }
    if (s.error != null && s.albums.isEmpty) {
      return _ErrorView(message: s.error!, onRetry: s.loadLibrary);
    }
    return RefreshIndicator(
      color: PA.accent,
      onRefresh: s.loadLibrary,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, childAspectRatio: 0.78, crossAxisSpacing: 12, mainAxisSpacing: 12),
        itemCount: s.albums.length,
        itemBuilder: (_, i) => AlbumCard(album: s.albums[i]),
      ),
    );
  }
}

class AlbumCard extends StatelessWidget {
  final Album album;
  const AlbumCard({super.key, required this.album});
  @override
  Widget build(BuildContext context) {
    final art = context.read<AppState>().bridge.artUrl(album.artPath, width: 300);
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => AlbumScreen(album: album))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: art != null
                  ? CachedNetworkImage(
                      imageUrl: art, fit: BoxFit.cover, width: double.infinity,
                      placeholder: (_, __) => Container(color: PA.card),
                      errorWidget: (_, __, ___) => const _ArtPlaceholder())
                  : const _ArtPlaceholder(),
            ),
          ),
          const SizedBox(height: 6),
          Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Text(album.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: PA.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}

class _ArtPlaceholder extends StatelessWidget {
  const _ArtPlaceholder();
  @override
  Widget build(BuildContext context) => Container(
      color: PA.surfaceElevated,
      child: const Center(child: Icon(Icons.music_note, color: PA.textMuted, size: 36)));
}

// ── Album screen ──────────────────────────────────────────────────────────────
class AlbumScreen extends StatelessWidget {
  final Album album;
  const AlbumScreen({super.key, required this.album});
  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final art = s.bridge.artUrl(album.artPath, width: 600);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300, pinned: true, backgroundColor: PA.background,
            flexibleSpace: FlexibleSpaceBar(
              background: art != null
                  ? CachedNetworkImage(imageUrl: art, fit: BoxFit.cover)
                  : const _ArtPlaceholder(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(album.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  Text(album.artist, style: const TextStyle(color: PA.textSecondary)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: PA.accent),
                    onPressed: () => s.playAlbum(album),
                    icon: const Icon(Icons.play_arrow, color: Colors.black),
                    label: const Text('Play', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
          SliverList.builder(
            itemCount: album.tracks.length,
            itemBuilder: (_, i) {
              final t = album.tracks[i];
              return ListTile(
                leading: Text('${i + 1}', style: const TextStyle(color: PA.textMuted)),
                title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: PA.textSecondary)),
                onTap: () => s.playAlbum(album, startIndex: i),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }
}

// ── Search (Soulseek) ─────────────────────────────────────────────────────────
class SearchTab extends StatefulWidget {
  const SearchTab({super.key});
  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  List<SlskFolder> _results = [];

  Future<void> _search() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() { _busy = true; _results = []; });
    try {
      final r = await context.read<AppState>().bridge.slskSearch(_ctrl.text.trim());
      if (mounted) setState(() => _results = r);
    } catch (_) {} finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _ctrl,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Search Soulseek…',
              filled: true, fillColor: PA.card,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _search),
              border: const OutlineInputBorder(borderSide: BorderSide.none),
            ),
          ),
        ),
        if (_busy) const LinearProgressIndicator(color: PA.accent, backgroundColor: PA.card),
        Expanded(
          child: ListView.builder(
            itemCount: _results.length,
            itemBuilder: (_, i) {
              final f = _results[i];
              return ListTile(
                title: Text(f.folder.split('\\').last, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${f.username} · ${f.fileCount} files'
                    '${f.bitrate != null ? ' · ${f.bitrate}kbps' : ''}',
                    style: const TextStyle(color: PA.textSecondary)),
                trailing: IconButton(
                  icon: const Icon(Icons.download, color: PA.accent),
                  onPressed: () {
                    context.read<AppState>().bridge.slskDownload(f);
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Download started on PC')));
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Library (placeholder for on-phone library, next pass) ─────────────────────
class LibraryTab extends StatelessWidget {
  const LibraryTab({super.key});
  @override
  Widget build(BuildContext context) => const Center(
      child: Text('On-phone library — coming next', style: TextStyle(color: PA.textSecondary)));
}

// ── Mini player ───────────────────────────────────────────────────────────────
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});
  @override
  Widget build(BuildContext context) {
    final ps = context.read<AppState>().playerService;
    return StreamBuilder<int?>(
      stream: ps.currentIndex,
      builder: (_, __) {
        final t = ps.currentTrack;
        if (t == null) return const SizedBox.shrink();
        final art = context.read<AppState>().bridge.artUrl(t.artPath, width: 120);
        return Container(
          height: 60,
          color: PA.surfaceElevated,
          child: Row(
            children: [
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: art != null
                    ? CachedNetworkImage(imageUrl: art, width: 44, height: 44, fit: BoxFit.cover)
                    : const SizedBox(width: 44, height: 44, child: _ArtPlaceholder()),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: PA.textSecondary, fontSize: 11)),
                  ],
                ),
              ),
              StreamBuilder<PlayerState>(
                stream: ps.playerState,
                builder: (_, snap) {
                  final playing = snap.data?.playing ?? false;
                  return IconButton(
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    onPressed: ps.togglePlay,
                  );
                },
              ),
              IconButton(icon: const Icon(Icons.skip_next), onPressed: ps.next),
            ],
          ),
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, color: PA.textMuted, size: 44),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: PA.textSecondary)),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: PA.accent),
              onPressed: onRetry,
              child: const Text('Retry', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      );
}
