import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../history.dart';
import '../models.dart';
import '../theme.dart';

/// Shows detailed metadata for a track in a bottom sheet.
void showTrackInfo(BuildContext context, Track track) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: PA.surfaceElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _TrackInfoSheet(track: track),
  );
}

class _TrackInfoSheet extends StatelessWidget {
  final Track track;
  const _TrackInfoSheet({required this.track});

  @override
  Widget build(BuildContext context) {
    final h = context.read<AppState>().history;
    final listenCount = h.listensOf(track);
    final firstEpoch = h.firstListen[track.key];
    final lastEpoch = h.lastListen[track.key];

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: PA.textMuted.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(track.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: PA.text)),
          const SizedBox(height: 4),
          Text('${track.artist}${track.album != null ? ' — ${track.album}' : ''}',
              style: const TextStyle(fontSize: 14, color: PA.textSecondary)),
          const Divider(height: 32, color: PA.separator),
          _row('File path', track.filePath),
          if (track.genre != null) _row('Genre', track.genre!),
          _row('Duration', _fmtDuration(track.duration)),
          _row('Track number', '${track.trackNumber}'),
          if (track.discNumber > 1) _row('Disc', '${track.discNumber}'),
          if (track.year > 0) _row('Year', '${track.year}'),
          _row('Listens', '$listenCount'),
          if (firstEpoch != null)
            _row('First listened', _fmtEpoch(firstEpoch)),
          if (lastEpoch != null)
            _row('Last listened', _fmtEpoch(lastEpoch)),
          const Divider(height: 32, color: PA.separator),
          Center(
            child: TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, size: 16, color: PA.textSecondary),
              label: const Text('Close', style: TextStyle(color: PA.textSecondary)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 120, child: Text(label,
            style: const TextStyle(color: PA.textMuted, fontSize: 13))),
        Expanded(child: Text(value,
            style: const TextStyle(color: PA.text, fontSize: 13))),
      ],
    ),
  );

  String _fmtDuration(double sec) {
    final m = (sec / 60).floor();
    final s = (sec % 60).floor();
    return '${m}:${s.toString().padLeft(2, '0')}';
  }

  String _fmtEpoch(int epochMs) {
    final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
