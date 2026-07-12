import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
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

  @override
  void initState() {
    super.initState();
    _refreshTransfers();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refreshTransfers());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refreshTransfers() async {
    final s = context.read<AppState>();
    if (!s.configured) return;
    final t = await s.bridge.slskTransfers();
    if (mounted) setState(() => _transfers = t);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final dm = s.downloads;
    return AnimatedBuilder(
      animation: dm,
      builder: (context, _) {
        final inFlight = dm.progress.entries.toList();
        return ListView(
          padding: const EdgeInsets.only(bottom: 80),
          children: [
            const _SectionHeader('On this phone'),
            if (dm.downloaded.isEmpty && inFlight.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                    'Nothing downloaded yet. Use the download button on any '
                    'album or track in Home to keep music for offline.',
                    style: TextStyle(color: PA.textSecondary, fontSize: 13)),
              ),
            ...inFlight.map((e) => ListTile(
                  leading: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(
                          child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: PA.accent)))),
                  title: Text(e.key.split(RegExp(r'[\\/]')).last,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: LinearProgressIndicator(
                      value: e.value > 0 ? e.value : null,
                      color: PA.accent,
                      backgroundColor: PA.card),
                )),
            ...dm.downloaded.asMap().entries.map((e) {
              final t = e.value;
              return ListTile(
                leading: TrackArt(
                    artUri: t.artUri, artPath: t.artPath, size: 40, px: 120),
                title: Text(t.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(t.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: PA.textSecondary)),
                onTap: () => s.playTrackInList(dm.downloaded, e.key),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: PA.textMuted),
                  onPressed: () => dm.remove(t.id),
                ),
              );
            }),
            const _SectionHeader('PC transfers (Soulseek)'),
            if (!s.configured)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('Connect to your PC to see transfers.',
                    style: TextStyle(color: PA.textSecondary, fontSize: 13)),
              )
            else if (_transfers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('No active transfers.',
                    style: TextStyle(color: PA.textSecondary, fontSize: 13)),
              ),
            ..._transfers.whereType<Map>().map((t) => _TransferTile(t: t)),
          ],
        );
      },
    );
  }
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
