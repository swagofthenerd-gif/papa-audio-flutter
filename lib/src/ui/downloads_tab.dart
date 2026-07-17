import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';

/// Two lists: tracks downloaded onto this phone (playable offline) and the
/// PC's live Soulseek transfers (polled while the tab is visible).
class DownloadsTab extends StatefulWidget {
  const DownloadsTab({super.key});
  @override
  State<DownloadsTab> createState() => _DownloadsTabState();
}

class _DownloadsTabState extends State<DownloadsTab> {
  Timer? _poll;
  List<dynamic> _transfers = [];
  ValueListenable<bool>? _visible; // TickerMode notifier from the shell
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    // Timer exists ONLY while the tab is visible and the app is foregrounded —
    // no wakeups with the screen off. (Perf audit finding.)
    _lifecycle = AppLifecycleListener(
      onResume: _syncPolling,
      onInactive: _stopPolling,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible?.removeListener(_syncPolling);
    _visible = TickerMode.getNotifier(context)..addListener(_syncPolling);
    _syncPolling();
  }

  void _syncPolling() {
    final shouldRun = _visible?.value ?? false;
    if (shouldRun && _poll == null) {
      _refreshTransfers();
      _poll = Timer.periodic(
          const Duration(seconds: 3), (_) => _refreshTransfers());
    } else if (!shouldRun) {
      _stopPolling();
    }
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  @override
  void dispose() {
    _visible?.removeListener(_syncPolling);
    _lifecycle?.dispose();
    _stopPolling();
    super.dispose();
  }

  Future<void> _refreshTransfers() async {
    final s = context.read<AppState>();
    if (!s.configured) return;
    final t = await s.bridge.slskTransfers();
    if (!mounted) return;
    // Skip the rebuild when nothing changed — polling mustn't cost frames.
    if (t.length == _transfers.length && '$t' == '$_transfers') return;
    setState(() => _transfers = t);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final dm = s.downloads;
    return AnimatedBuilder(
      animation: dm,
      builder: (context, _) {
        // Flattened, LAZY list: only visible rows are ever built, so progress
        // notifies never rebuild hundreds of tiles. (Perf audit finding.)
        final inFlight = dm.progress.entries.toList();
        final transfers = _transfers.whereType<Map>().toList();
        final items = <Object>[
          const _SectionHeader('On this phone'),
          if (dm.downloaded.isEmpty && inFlight.isEmpty) const _EmptyNote(
              'Nothing downloaded yet. Use the download button on any '
              'album or track in Home to keep music for offline.'),
          ...inFlight,
          ...dm.downloaded,
          const _SectionHeader('PC transfers (Soulseek)'),
          if (!s.configured)
            const _EmptyNote('Connect to your PC to see transfers.')
          else if (transfers.isEmpty)
            const _EmptyNote('No active transfers.'),
          ...transfers,
        ];
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 80),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final item = items[i];
            if (item is Widget) return item;
            if (item is MapEntry<String, double>) {
              return ListTile(
                leading: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                        child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: PA.accent)))),
                title: Text(item.key.split(RegExp(r'[\\/]')).last,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: LinearProgressIndicator(
                    value: item.value > 0 ? item.value : null,
                    color: PA.accent,
                    backgroundColor: PA.card),
              );
            }
            if (item is Track) {
              return ListTile(
                leading: TrackArt(
                    artUri: item.artUri, artPath: item.artPath, size: 40, px: 120),
                title: Text(item.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(item.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: PA.textSecondary)),
                onTap: () => s.playTrackInList(
                    dm.downloaded, dm.downloaded.indexOf(item)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: PA.textMuted),
                  onPressed: () => dm.remove(item.id),
                ),
              );
            }
            return _TransferTile(t: item as Map);
          },
        );
      },
    );
  }
}

class _EmptyNote extends StatelessWidget {
  final String text;
  const _EmptyNote(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(text,
            style: const TextStyle(color: PA.textSecondary, fontSize: 13)),
      );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(title,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: PA.text)),
      );
}

/// One PC-side Soulseek transfer. Field names vary by server version, so parse
/// generously: file/filename/name, state/status, progress/percent 0..1 or 0..100.
class _TransferTile extends StatelessWidget {
  final Map t;
  const _TransferTile({required this.t});

  @override
  Widget build(BuildContext context) {
    final name = (t['file'] ?? t['filename'] ?? t['name'] ?? '')
        .toString()
        .split(RegExp(r'[\\/]'))
        .last;
    final state = (t['state'] ?? t['status'] ?? '').toString();
    var progress =
        ((t['progress'] ?? t['percent'] ?? 0) as num).toDouble();
    if (progress > 1) progress /= 100;
    final done = state.toLowerCase().contains('complete') || progress >= 1;
    return ListTile(
      leading: Icon(
        done ? Icons.check_circle : Icons.swap_vert,
        color: done ? PA.accent : PA.textSecondary,
      ),
      title: Text(name.isEmpty ? 'Unknown file' : name,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: done
          ? Text(state.isEmpty ? 'Complete' : state,
              style: const TextStyle(color: PA.textSecondary, fontSize: 12))
          : LinearProgressIndicator(
              value: progress > 0 ? progress.clamp(0.0, 1.0) : null,
              color: PA.accent,
              backgroundColor: PA.card),
    );
  }
}
