import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../local_library.dart';
import '../theme.dart';

/// One artwork widget for every source the app plays from:
/// http(s) → network image, file:// → local file, localart:// → MediaStore
/// bytes over the platform channel, null → bridge /art fallback via [artPath].
class TrackArt extends StatelessWidget {
  final String? artUri;
  final String? artPath; // bridge fallback key
  final double size;
  final double radius;
  final int px; // requested pixel width for network/MediaStore art

  const TrackArt({
    super.key,
    this.artUri,
    this.artPath,
    required this.size,
    this.radius = 4,
    int? px,
  }) : px = px ?? 300;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: size, height: size, child: _image(context)),
    );
  }

  Widget _image(BuildContext context) {
    // Decode no larger than the slot actually needs (in physical pixels) — a
    // 44px tile must never pay for a 1400px embedded-art decode.
    final decodePx = (px * MediaQuery.devicePixelRatioOf(context) / 2)
        .round()
        .clamp(64, 1600)
        .toInt();
    final a = artUri;
    if (a != null && a.startsWith('localart://')) {
      return FutureBuilder<Uint8List?>(
        future: LocalLibrary.artForUri(a, size: px),
        builder: (_, snap) => snap.data != null
            ? Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true)
            : const ArtPlaceholder(),
      );
    }
    if (a != null && a.startsWith('file:')) {
      return Image.file(
        File.fromUri(Uri.parse(a)),
        fit: BoxFit.cover,
        cacheWidth: decodePx,
        errorBuilder: (_, _, _) => const ArtPlaceholder(),
      );
    }
    final url = (a != null && a.startsWith('http'))
        ? a
        : context.read<AppState>().bridge.artUrl(artPath, width: px);
    if (url == null) return const ArtPlaceholder();
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: decodePx,
      placeholder: (_, _) => Container(color: PA.card),
      errorWidget: (_, _, _) => const ArtPlaceholder(),
    );
  }
}

class ArtPlaceholder extends StatelessWidget {
  const ArtPlaceholder({super.key});
  @override
  Widget build(BuildContext context) => Container(
      color: PA.surfaceElevated,
      child: const Center(child: Icon(Icons.music_note, color: PA.textMuted, size: 36)));
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorView({super.key, required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, color: PA.textMuted, size: 44),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: PA.textSecondary)),
            ),
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

/// 215.0 → "3:35"; over an hour → "1:02:35".
String fmtDuration(double seconds) {
  final d = Duration(seconds: seconds.round());
  String two(int n) => n.toString().padLeft(2, '0');
  if (d.inHours > 0) return '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  return '${d.inMinutes}:${two(d.inSeconds % 60)}';
}
