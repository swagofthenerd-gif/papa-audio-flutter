import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'src/app_state.dart';
import 'src/models.dart';
import 'src/theme.dart';
import 'src/ui/downloads_tab.dart';
import 'src/ui/library_tab.dart';
import 'src/ui/player_sheet.dart';
import 'src/ui/search_tab.dart';
import 'src/ui/selection_bar.dart';
import 'src/ui/track_tile.dart';
import 'src/ui/widgets.dart';

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
  // Restore the saved bridge + load libraries AFTER the UI is up.
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
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Connect',
                          style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shell: pages + nav bar + the persistent player sheet overlay ─────────────
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  static const _pages = [HomeTab(), SearchTab(), LibraryTab(), DownloadsTab()];

  @override
  Widget build(BuildContext context) {
    final ps = context.read<AppState>().playerService;
    final navHeight = 80.0 + MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: SafeArea(
                  bottom: false,
                  // TickerMode lets hidden tabs know they're offscreen, so
                  // they can pause timers/polling (see DownloadsTab).
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      for (var i = 0; i < _pages.length; i++)
                        TickerMode(enabled: i == _tab, child: _pages[i]),
                    ],
                  ),
                ),
              ),
              const SelectionBar(),
              // Reserve the mini player's slot when a track is loaded.
              StreamBuilder<int?>(
                stream: ps.currentIndex,
                builder: (_, _) => SizedBox(
                    height: ps.currentTrack != null
                        ? PlayerSheet.miniHeight
                        : 0),
              ),
              NavigationBar(
                backgroundColor: PA.surface,
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                destinations: const [
                  NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: 'Home'),
                  NavigationDestination(
                      icon: Icon(Icons.search), label: 'Search'),
                  NavigationDestination(
                      icon: Icon(Icons.library_music_outlined),
                      selectedIcon: Icon(Icons.library_music),
                      label: 'Library'),
                  NavigationDestination(
                      icon: Icon(Icons.download_outlined),
                      selectedIcon: Icon(Icons.download),
                      label: 'Downloads'),
                ],
              ),
            ],
          ),
          Positioned.fill(child: PlayerSheet(navHeight: navHeight)),
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
      return ErrorView(message: s.error!, onRetry: s.loadLibrary);
    }
    return RefreshIndicator(
      color: PA.accent,
      onRefresh: s.loadLibrary,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.78,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12),
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
    final art =
        context.read<AppState>().bridge.artUrl(album.artPath, width: 300);
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
                      imageUrl: art,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      placeholder: (_, _) => Container(color: PA.card),
                      errorWidget: (_, _, _) => const ArtPlaceholder())
                  : const ArtPlaceholder(),
            ),
          ),
          const SizedBox(height: 6),
          Text(album.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Text(album.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: PA.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}

// ── Album screen (PC library) ─────────────────────────────────────────────────
class AlbumScreen extends StatelessWidget {
  final Album album;
  const AlbumScreen({super.key, required this.album});
  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final art = s.bridge.artUrl(album.artPath, width: 600);
    return Scaffold(
      bottomNavigationBar: const SelectionBar(),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: PA.background,
            flexibleSpace: FlexibleSpaceBar(
              background: art != null
                  ? CachedNetworkImage(imageUrl: art, fit: BoxFit.cover)
                  : const ArtPlaceholder(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(album.name,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                  Text(album.artist,
                      style: const TextStyle(color: PA.textSecondary)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      PlayShuffleRow(tracks: album.tracks),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: PA.accent,
                            side: const BorderSide(color: PA.accent)),
                        onPressed: () {
                          s.downloads.downloadAlbum(album, s.bridge);
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Downloading album to this phone…')));
                        },
                        icon: const Icon(Icons.download),
                        label: const Text('Download'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverList.builder(
            itemCount: album.tracks.length,
            itemBuilder: (_, i) {
              final t = album.tracks[i];
              return TrackTile(
                track: t,
                showArt: false,
                leading: SizedBox(
                    width: 24,
                    child: Center(
                        child: Text('${i + 1}',
                            style: const TextStyle(color: PA.textMuted)))),
                trailingExtra: _TrackDownloadButton(track: t),
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

/// Per-track download state: idle → spinner → check.
class _TrackDownloadButton extends StatelessWidget {
  final Track track;
  const _TrackDownloadButton({required this.track});
  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return AnimatedBuilder(
      animation: s.downloads,
      builder: (context, _) {
        if (s.downloads.isDownloaded(track.id)) {
          return const Padding(
            padding: EdgeInsets.only(right: 4),
            child: Icon(Icons.check_circle, color: PA.accent, size: 18),
          );
        }
        final p = s.downloads.progress[track.id];
        if (p != null) {
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, value: p > 0 ? p : null, color: PA.accent),
            ),
          );
        }
        return IconButton(
          icon: const Icon(Icons.download_outlined,
              color: PA.textMuted, size: 18),
          onPressed: () => s.downloads.download(track, s.bridge),
        );
      },
    );
  }
}
