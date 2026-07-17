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
    final seed = artUri ?? artPath;
    final placeholder = ArtPlaceholder(seed: seed);
    final a = artUri;
    if (a != null && a.startsWith('localart://')) {
      return FutureBuilder<Uint8List?>(
        future: LocalLibrary.artForUri(a, size: px),
        builder: (_, snap) => snap.data != null
            ? Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true)
            : placeholder,
      );
    }
    if (a != null && a.startsWith('file:')) {
      return Image.file(
        File.fromUri(Uri.parse(a)),
        fit: BoxFit.cover,
        cacheWidth: decodePx,
        errorBuilder: (_, _, _) => placeholder,
      );
    }
    final url = (a != null && a.startsWith('http'))
        ? a
        : context.read<AppState>().bridge.artUrl(artPath, width: px);
    if (url == null) return placeholder;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: decodePx,
      placeholder: (_, _) => const ColoredBox(color: PA.card),
      errorWidget: (_, _, _) => placeholder,
    );
  }
}

class ArtPlaceholder extends StatelessWidget {
  /// When set, the placeholder derives a stable hue from this string so art-less
  /// tiles look intentionally designed (and distinct) rather than uniformly grey.
  final String? seed;
  const ArtPlaceholder({super.key, this.seed});

  @override
  Widget build(BuildContext context) {
    final s = seed;
    final Gradient gradient;
    if (s != null && s.isNotEmpty) {
      final hue = (s.hashCode & 0x7fffffff) % 360;
      final base = HSLColor.fromAHSL(1, hue.toDouble(), 0.32, 0.26).toColor();
      final dark = HSLColor.fromAHSL(1, hue.toDouble(), 0.30, 0.14).toColor();
      gradient = LinearGradient(
          colors: [base, dark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight);
    } else {
      gradient = const LinearGradient(
          colors: [PA.surfaceElevated, PA.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight);
    }
    return DecoratedBox(
      decoration: BoxDecoration(gradient: gradient),
      // Icon scales with the slot so the placeholder reads correctly at any
      // size (incl. inside the player's FittedBox-scaled morphing artwork).
      child: LayoutBuilder(
        builder: (_, c) {
          final side = c.hasBoundedWidth && c.hasBoundedHeight
              ? (c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight)
              : 44.0;
          return Center(
              child: Icon(Icons.music_note,
                  color: Colors.white.withValues(alpha: 0.32),
                  size: (side * 0.5).clamp(12.0, 96.0)));
        },
      ),
    );
  }
}

/// Cached network image with the shared placeholder — used for YouTube
/// thumbnails (http URLs that never map to a Track/artUri).
///
/// [slotPx] is the logical size of the slot this fills; the image is decoded to
/// no more than that (× devicePixelRatio, capped), so a wall of 150px cards
/// never holds full-resolution bitmaps in memory — the difference between a
/// smooth hours-long browse and a slow OOM crash.
class NetworkArt extends StatelessWidget {
  final String url;
  final double slotPx;
  const NetworkArt({super.key, required this.url, this.slotPx = 200});
  @override
  Widget build(BuildContext context) {
    final decodePx = (slotPx * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(64, 720);
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: decodePx,
      placeholder: (_, _) => const ColoredBox(color: PA.card),
      errorWidget: (_, _, _) => ArtPlaceholder(seed: url),
    );
  }
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
