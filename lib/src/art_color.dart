import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'local_library.dart';
import 'models.dart';

/// Extracts a representative color from a track's artwork for player theming.
/// No dependencies: decode small, bucket pixels by hue, prefer saturated
/// buckets weighted by population, then clamp brightness for dark UI use.
class ArtColorService {
  final String? Function(String? artPath) bridgeArtUrl;
  ArtColorService({required this.bridgeArtUrl});

  static const _cap = 64;
  final Map<String, Future<Color?>> _cache = {}; // LRU by re-insert

  Future<Color?> forTrack(Track t) {
    final key = t.artUri ?? t.artPath ?? t.key;
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return hit;
    }
    final future = _extract(t);
    _cache[key] = future;
    while (_cache.length > _cap) {
      _cache.remove(_cache.keys.first);
    }
    return future;
  }

  Future<Color?> _extract(Track t) async {
    try {
      final bytes = await _artBytes(t);
      if (bytes == null) return null;
      final codec = await ui.instantiateImageCodec(bytes,
          targetWidth: 48, targetHeight: 48);
      final frame = await codec.getNextFrame();
      final data =
          await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      frame.image.dispose();
      if (data == null) return null;
      return _dominant(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _artBytes(Track t) async {
    final a = t.artUri;
    if (a != null && a.startsWith('localart://')) {
      return LocalLibrary.artForUri(a, size: 96);
    }
    if (a != null && a.startsWith('file:')) {
      return File.fromUri(Uri.parse(a)).readAsBytes();
    }
    final url =
        (a != null && a.startsWith('http')) ? a : bridgeArtUrl(t.artPath);
    if (url == null) return null;
    // Reuse the image cache CachedNetworkImage already populates.
    final file = await DefaultCacheManager().getSingleFile(url);
    return file.readAsBytes();
  }

  /// 12 hue buckets + a neutral bucket; score = population × (saturation
  /// boosted), so a vivid accent beats a large gray background.
  static Color? _dominant(Uint8List rgba) {
    final scores = List<double>.filled(13, 0);
    final sums = List<double>.filled(13 * 3, 0);
    final counts = List<int>.filled(13, 0);
    for (var i = 0; i + 3 < rgba.length; i += 4) {
      final r = rgba[i] / 255.0, g = rgba[i + 1] / 255.0, b = rgba[i + 2] / 255.0;
      if (rgba[i + 3] < 128) continue;
      final hsv = HSVColor.fromColor(
          Color.from(alpha: 1, red: r, green: g, blue: b));
      final bucket =
          hsv.saturation < 0.15 ? 12 : (hsv.hue / 30).floor().clamp(0, 11);
      final weight = bucket == 12 ? 0.05 : 0.2 + hsv.saturation;
      scores[bucket] += weight * (0.3 + hsv.value);
      sums[bucket * 3] += r;
      sums[bucket * 3 + 1] += g;
      sums[bucket * 3 + 2] += b;
      counts[bucket]++;
    }
    var best = -1;
    var bestScore = 0.0;
    for (var i = 0; i < 13; i++) {
      if (counts[i] > 0 && scores[i] > bestScore) {
        bestScore = scores[i];
        best = i;
      }
    }
    if (best < 0) return null;
    final n = counts[best];
    final avg = Color.from(
      alpha: 1,
      red: sums[best * 3] / n,
      green: sums[best * 3 + 1] / n,
      blue: sums[best * 3 + 2] / n,
    );
    // Dark-theme friendly: keep hue, cap brightness, ensure some saturation.
    final hsv = HSVColor.fromColor(avg);
    return hsv
        .withValue(math.min(hsv.value, 0.55))
        .withSaturation(hsv.saturation.clamp(0.25, 0.85))
        .toColor();
  }
}
