import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, SystemNavigator;
import 'package:provider/provider.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'src/app_state.dart';
import 'src/models.dart';
import 'src/theme.dart';
import 'src/ui/collection_menu.dart';
import 'src/ui/downloads_tab.dart';
import 'src/ui/home_tab.dart';
import 'src/ui/library_tab.dart';
import 'src/ui/music_hub.dart';
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
    final s = context.read<AppState>();
    // Rebuild the whole app (fresh theme + PA-colored widgets) when settings
    // that affect appearance change — the AMOLED toggle swaps PA surfaces.
    return AnimatedBuilder(
      animation: s.settings,
      builder: (context, _) => MaterialApp(
        title: 'Papa Audio',
        debugShowCheckedModeBanner: false,
        theme: papaTheme(),
        // App-wide bouncy scroll (with a glow fallback for reduced-motion), so
        // every list has the same tactile "give" Namida is known for.
        scrollBehavior: const _PapaScrollBehavior(),
        home: const Root(),
      ),
    );
  }
}

/// Bouncy overscroll on all platforms. Applied globally via
/// MaterialApp.scrollBehavior. BouncingScrollPhysics provides the "give"
/// itself, so no separate overscroll indicator is needed.
class _PapaScrollBehavior extends MaterialScrollBehavior {
  const _PapaScrollBehavior();
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  @override
  Widget buildOverscrollIndicator(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child; // bounce handles overscroll; no glow/stretch overlay
}

class Root extends StatelessWidget {
  const Root({super.key});
  @override
  Widget build(BuildContext context) {
    final ready = context.select<AppState, bool>((s) => s.ready);
    return ready ? const Shell() : const SetupScreen();
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
              const SizedBox(height: 8),
              // Local-library users don't need a PC — let them straight in.
              TextButton(
                onPressed: _busy
                    ? null
                    : () => context.read<AppState>().enterLocalOnly(),
                child: const Text('Skip — use only music on this phone',
                    style: TextStyle(color: PA.textSecondary)),
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

  /// Registered by the live shell state — lets deep leaves (e.g. a snackbar
  /// "VIEW" action) switch the bottom tab without threading callbacks through
  /// every screen. Tabs: 0 Home, 1 Search, 2 Library, 3 Downloads.
  static void Function(int index)? switchTo;

  /// The nested content navigator. Screens pushed here slide in UNDER the
  /// mini player and nav bar, so the player stays visible on every screen.
  /// Pushes from tab screens land here automatically (nearest Navigator);
  /// code living OUTSIDE it (player sheet, modal sheets) routes through
  /// [contentContext].
  static final GlobalKey<NavigatorState> contentNav =
      GlobalKey<NavigatorState>();

  /// Context inside the content navigator, for pushes initiated from
  /// overlays; falls back to the caller's own context pre-shell.
  static BuildContext contentContext(BuildContext fallback) =>
      contentNav.currentContext ?? fallback;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final ValueNotifier<int> _tab = ValueNotifier(0);
  static const _pages = [HomeTab(), SearchTab(), LibraryTab(), DownloadsTab()];

  @override
  void initState() {
    super.initState();
    Shell.switchTo = (i) {
      if (!mounted) return;
      Shell.contentNav.currentState?.popUntil((r) => r.isFirst);
      _tab.value = i.clamp(0, _pages.length - 1);
    };
  }

  @override
  void dispose() {
    if (Shell.switchTo != null) Shell.switchTo = null;
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ps = context.read<AppState>().playerService;
    final navHeight = 80.0 + MediaQuery.paddingOf(context).bottom;
    // ONE back handler for the whole shell, in priority order: the player
    // sheet (queue panel, then expanded player), then pushed content screens,
    // then leave the app. Split PopScopes would all fire on a single press.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (PlayerSheet.backHandler?.call() ?? false) return;
        final nav = Shell.contentNav.currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
          return;
        }
        SystemNavigator.pop();
      },
      child: Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: SafeArea(
                  bottom: false,
                  child: Navigator(
                      key: Shell.contentNav,
                      onGenerateRoute: (_) => MaterialPageRoute(
                        builder: (_) => ValueListenableBuilder<int>(
                          valueListenable: _tab,
                          // TickerMode lets hidden tabs know they're
                          // offscreen, so they can pause timers/polling
                          // (see DownloadsTab).
                          builder: (_, tab, _) => IndexedStack(
                            index: tab,
                            children: [
                              for (var i = 0; i < _pages.length; i++)
                                TickerMode(
                                    enabled: i == tab, child: _pages[i]),
                            ],
                          ),
                        ),
                      ),
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
              ValueListenableBuilder<int>(
                valueListenable: _tab,
                builder: (_, tab, _) => NavigationBar(
                backgroundColor: PA.surface,
                selectedIndex: tab,
                onDestinationSelected: (i) {
                  HapticFeedback.selectionClick();
                  // Tab tap clears any pushed screen so the tab itself shows.
                  Shell.contentNav.currentState?.popUntil((r) => r.isFirst);
                  _tab.value = i;
                },
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
              ),
            ],
          ),
          Positioned.fill(child: PlayerSheet(navHeight: navHeight)),
        ],
        ),
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
      onLongPress: () => showCollectionMenu(context,
          title: album.name, tracks: album.tracks),
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
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => openArtistName(
                        context, context.read<AppState>(), album.artist),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(album.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: PA.textSecondary)),
                        ),
                        const Icon(Icons.chevron_right,
                            size: 18, color: PA.textMuted),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      PlayShuffleRow(
                          tracks: album.tracks,
                          collectionId: 'palbum:${album.id}'),
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
