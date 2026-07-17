import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../player_service.dart';
import '../theme.dart';
import 'music_hub.dart';
import 'widgets.dart';

/// Long-press / ⋮ menu for any track, from any list. Actions apply across
/// sources (PC, local, downloaded, YouTube) — unavailable ones are hidden.
void showTrackMenu(BuildContext context, Track t) {
  final s = context.read<AppState>();
  showModalBottomSheet(
    context: context,
    backgroundColor: PA.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (sheetCtx) {
      final fav = s.playlists.isFavorite(t);
      final isYt = t.id.startsWith('yt:');
      final canDownload =
          t.sourceUri == null && t.filePath.isNotEmpty && s.configured;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  TrackArt(artUri: t.artUri, artPath: t.artPath, size: 44, px: 120),
              title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(t.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: PA.textSecondary)),
            ),
            const Divider(height: 1, color: PA.separator),
            _MenuItem(
              icon: Icons.playlist_play,
              label: 'Play next',
              onTap: () {
                s.playerService.playNext(t);
                Navigator.pop(sheetCtx);
              },
            ),
            _MenuItem(
              icon: Icons.queue,
              label: 'Add to queue',
              onTap: () {
                s.playerService.addToQueue(t);
                Navigator.pop(sheetCtx);
              },
            ),
            if (isYt)
              _MenuItem(
                icon: Icons.radio,
                label: 'Start radio',
                onTap: () {
                  s.playYtTrack(t);
                  Navigator.pop(sheetCtx);
                },
              ),
            _MenuItem(
              icon: fav ? Icons.favorite : Icons.favorite_border,
              label: fav ? 'Remove from favorites' : 'Add to favorites',
              color: fav ? PA.accent : null,
              onTap: () {
                s.playlists.toggleFavorite(t);
                Navigator.pop(sheetCtx);
              },
            ),
            _MenuItem(
              icon: Icons.playlist_add,
              label: 'Add to playlist…',
              onTap: () {
                Navigator.pop(sheetCtx);
                showAddToPlaylistSheet(context, [t]);
              },
            ),
            _MenuItem(
              icon: Icons.person_outline,
              label: 'Go to artist',
              onTap: () {
                Navigator.pop(sheetCtx);
                openArtist(context, s, t);
              },
            ),
            if (t.album != null && t.album!.trim().isNotEmpty)
              _MenuItem(
                icon: Icons.album_outlined,
                label: 'Go to album',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  openAlbum(context, s, t);
                },
              ),
            if (canDownload)
              _MenuItem(
                icon: Icons.download_outlined,
                label: 'Download to this phone',
                onTap: () {
                  s.downloads.download(t, s.bridge);
                  Navigator.pop(sheetCtx);
                },
              ),
            if (isYt)
              _MenuItem(
                icon: Icons.download_outlined,
                label: 'Download to this phone',
                onTap: () {
                  s.downloads.downloadYt(t, s.yt.resolver);
                  Navigator.pop(sheetCtx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Downloading — see the Downloads tab')));
                },
              ),
            _MenuItem(
              icon: Icons.info_outline,
              label: 'Track info',
              onTap: () {
                Navigator.pop(sheetCtx);
                showTrackInfo(context, t);
              },
            ),
          ],
        ),
      );
    },
  );
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;
  const _MenuItem(
      {required this.icon, required this.label, this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: color ?? PA.textSecondary, size: 22),
        title: Text(label, style: const TextStyle(fontSize: 14)),
        onTap: onTap,
        dense: true,
      );
}

void showAddToPlaylistSheet(BuildContext context, List<Track> tracks) {
  final s = context.read<AppState>();
  showModalBottomSheet(
    context: context,
    backgroundColor: PA.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (sheetCtx) => AnimatedBuilder(
      animation: s.playlists,
      builder: (_, _) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                  tracks.length == 1
                      ? 'Add to playlist'
                      : 'Add ${tracks.length} tracks to playlist',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.add, color: PA.accent),
              title: const Text('New playlist'),
              onTap: () async {
                final name = await promptText(sheetCtx, 'New playlist', 'Name');
                if (name == null) return;
                final p = await s.playlists.create(name);
                await s.playlists.addTracks(p, tracks);
                if (sheetCtx.mounted) Navigator.pop(sheetCtx);
              },
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in s.playlists.playlists)
                    ListTile(
                      leading:
                          const Icon(Icons.queue_music, color: PA.textSecondary),
                      title: Text(p.name),
                      subtitle: Text('${p.tracks.length} tracks',
                          style: const TextStyle(
                              color: PA.textMuted, fontSize: 12)),
                      onTap: () async {
                        await s.playlists.addTracks(p, tracks);
                        if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<String?> promptText(BuildContext context, String title, String hint,
    {String? initial}) async {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dCtx) => AlertDialog(
      backgroundColor: PA.surfaceElevated,
      title: Text(title, style: const TextStyle(fontSize: 17)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(dCtx, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dCtx), child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(dCtx, ctrl.text),
            child: const Text('OK', style: TextStyle(color: PA.accent))),
      ],
    ),
  ).then((v) => (v == null || v.trim().isEmpty) ? null : v.trim());
}

void showTrackInfo(BuildContext context, Track t) {
  final rows = <(String, String)>[
    ('Title', t.title),
    ('Artist', t.artist),
    if (t.album != null) ('Album', t.album!),
    if (t.duration > 0) ('Duration', fmtDuration(t.duration)),
    if (t.trackNumber > 0) ('Track #', '${t.trackNumber}'),
    if (t.discNumber > 1) ('Disc', '${t.discNumber}'),
    if (t.filePath.isNotEmpty) ('Path', t.filePath),
    if (t.sourceUri != null) ('Source', t.sourceUri!),
  ];
  final listens = context.read<AppState>().history.listensOf(t);
  rows.add(('Listens', '$listens'));
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: PA.surfaceElevated,
      title: const Text('Track info', style: TextStyle(fontSize: 17)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (k, v) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                        width: 76,
                        child: Text(k,
                            style: const TextStyle(
                                color: PA.textMuted, fontSize: 12))),
                    Expanded(
                        child: Text(v, style: const TextStyle(fontSize: 12))),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

void showSleepTimerSheet(BuildContext context, PlayerService ps) {
  showModalBottomSheet(
    context: context,
    backgroundColor: PA.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (sheetCtx) => SafeArea(
      child: ValueListenableBuilder<SleepTimerState?>(
        valueListenable: ps.sleepTimer,
        builder: (_, active, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('Sleep timer',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            if (active != null)
              ListTile(
                leading: const Icon(Icons.bedtime, color: PA.accent),
                title: Text(active.endsAt != null
                    ? 'Stopping at ${TimeOfDay.fromDateTime(active.endsAt!).format(sheetCtx)}'
                    : 'Stopping after ${active.tracksLeft} more tracks'),
                trailing: TextButton(
                  onPressed: () {
                    ps.cancelSleepTimer();
                    Navigator.pop(sheetCtx);
                  },
                  child:
                      const Text('Cancel', style: TextStyle(color: PA.error)),
                ),
              ),
            Wrap(
              spacing: 8,
              children: [
                for (final m in [15, 30, 45, 60, 90])
                  ActionChip(
                    backgroundColor: PA.card,
                    label: Text('$m min'),
                    onPressed: () {
                      ps.startSleepTimer(minutes: m);
                      Navigator.pop(sheetCtx);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final n in [1, 2, 3, 5, 10])
                  ActionChip(
                    backgroundColor: PA.card,
                    label: Text('$n track${n > 1 ? 's' : ''}'),
                    onPressed: () {
                      ps.startSleepTimer(tracks: n);
                      Navigator.pop(sheetCtx);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 18),
          ],
        ),
      ),
    ),
  );
}

void showSpeedSheet(BuildContext context, PlayerService ps) {
  showModalBottomSheet(
    context: context,
    backgroundColor: PA.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (sheetCtx) => SafeArea(
      child: StreamBuilder<double>(
        stream: ps.speedStream,
        builder: (_, speedSnap) {
          final v = speedSnap.data ?? ps.speed;
          return StreamBuilder<double>(
            stream: ps.pitchStream,
            builder: (_, pitchSnap) {
              final p = pitchSnap.data ?? ps.pitch;
              // Pitch as musical semitones relative to normal (12 per octave).
              final semis = (12 * (math.log(p) / math.log(2)));
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text('Speed · ${v.toStringAsFixed(2)}x',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(sheetCtx).copyWith(
                      activeTrackColor: PA.accent,
                      inactiveTrackColor: PA.card,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: v.clamp(0.5, 2.0),
                      min: 0.5,
                      max: 2.0,
                      divisions: 30,
                      onChanged: (nv) => ps.setSpeed(nv),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final s in [0.75, 1.0, 1.25, 1.5, 2.0])
                        ActionChip(
                          backgroundColor: s == v ? PA.accent : PA.card,
                          label: Text('${s}x',
                              style: TextStyle(
                                  color: s == v ? Colors.black : PA.text)),
                          onPressed: () => ps.setSpeed(s),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
                    child: Text(
                        'Pitch · ${semis >= 0 ? '+' : ''}${semis.toStringAsFixed(1)} semitones',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(sheetCtx).copyWith(
                      activeTrackColor: PA.accent,
                      inactiveTrackColor: PA.card,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: semis.clamp(-12.0, 12.0),
                      min: -12,
                      max: 12,
                      divisions: 48, // quarter-semitone steps
                      onChanged: (ns) =>
                          ps.setPitch(math.pow(2, ns / 12).toDouble()),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ActionChip(
                        backgroundColor: PA.card,
                        label: const Text('432 Hz'),
                        tooltip: 'Tune A440 recordings down to A432',
                        onPressed: () => ps.setPitch(432 / 440),
                      ),
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: () {
                          ps.setSpeed(1.0);
                          ps.setPitch(1.0);
                        },
                        child: const Text('Reset',
                            style: TextStyle(color: PA.accent)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              );
            },
          );
        },
      ),
    ),
  );
}
