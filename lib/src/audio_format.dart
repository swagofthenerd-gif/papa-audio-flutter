import 'package:flutter/services.dart';

import 'models.dart';
import 'yt/yt_models.dart';

/// The audio quality of the currently-playing track, for the "now playing"
/// readout: a short badge (LOSSLESS / HI-RES / 320) plus a detail line
/// ("FLAC · 1055 kbps · 44.1 kHz").
class AudioFormat {
  final String codec; // FLAC, MP3, AAC, OPUS, ALAC, WAV…
  final int? bitrateKbps;
  final int? sampleRateHz;
  final int? bitDepth;
  final int? channels;
  const AudioFormat({
    required this.codec,
    this.bitrateKbps,
    this.sampleRateHz,
    this.bitDepth,
    this.channels,
  });

  static const _lossless = {'FLAC', 'ALAC', 'WAV', 'AIFF', 'PCM'};

  bool get isLossless => _lossless.contains(codec);
  bool get isHiRes =>
      isLossless && ((sampleRateHz ?? 0) > 48000 || (bitDepth ?? 0) > 16);

  /// Short badge shown next to the title.
  String get badge {
    if (isHiRes) return 'HI-RES';
    if (isLossless) return 'LOSSLESS';
    final b = bitrateKbps ?? 0;
    if (b >= 320) return '320';
    if (b >= 256) return '256';
    if (b > 0) return '${b}k';
    return codec;
  }

  /// Full detail line: "FLAC · 1055 kbps · 44.1 kHz · 24-bit".
  String get detailLine {
    final parts = <String>[codec];
    if (bitrateKbps != null) parts.add('$bitrateKbps kbps');
    if (sampleRateHz != null) {
      final khz = (sampleRateHz! / 1000);
      parts.add('${khz == khz.roundToDouble() ? khz.toStringAsFixed(0) : khz.toStringAsFixed(1)} kHz');
    }
    if (bitDepth != null && isLossless) parts.add('$bitDepth-bit');
    return parts.join(' · ');
  }
}

/// Resolves and caches the [AudioFormat] of tracks. YouTube formats come from
/// the resolved stream; local/PC files are probed natively (MediaExtractor).
class AudioFormatService {
  static const _ch = MethodChannel('papa.audio/media_store');
  final Map<String, AudioFormat> _cache = {};

  /// The YT resolver, so we can read the picked stream's bitrate/codec.
  final Future<YtStream> Function(String videoId)? _resolveYt;
  AudioFormatService({Future<YtStream> Function(String videoId)? resolveYt})
      : _resolveYt = resolveYt;

  Future<AudioFormat?> forTrack(Track t) async {
    final hit = _cache[t.key];
    if (hit != null) return hit;
    final fmt = await _resolve(t);
    if (fmt != null) _cache[t.key] = fmt;
    return fmt;
  }

  Future<AudioFormat?> _resolve(Track t) async {
    if (t.id.startsWith('yt:')) {
      final resolve = _resolveYt;
      if (resolve == null) return null;
      try {
        final s = await resolve(t.id.substring(3));
        return AudioFormat(
          codec: _codecFromMime(s.mime),
          bitrateKbps: s.bitrate > 0 ? (s.bitrate / 1000).round() : null,
        );
      } catch (_) {
        return null;
      }
    }
    // Local / PC file: probe natively.
    final uri = t.sourceUri;
    if (uri == null) return null;
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>(
          'audioFormat', {'uri': uri});
      if (r == null) return null;
      final mime = (r['mime'] ?? '').toString();
      final br = (r['bitrate'] as num?)?.toInt();
      return AudioFormat(
        codec: _codecFromMime(mime, path: t.filePath),
        bitrateKbps: br != null && br > 0 ? (br / 1000).round() : null,
        sampleRateHz: (r['sampleRate'] as num?)?.toInt(),
        bitDepth: (r['bitDepth'] as num?)?.toInt(),
        channels: (r['channels'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  static String _codecFromMime(String mime, {String? path}) {
    final m = mime.toLowerCase();
    if (m.contains('flac')) return 'FLAC';
    if (m.contains('alac')) return 'ALAC';
    if (m.contains('opus')) return 'OPUS';
    if (m.contains('vorbis') || m.contains('ogg')) return 'OGG';
    if (m.contains('mp3') || m.contains('mpeg')) return 'MP3';
    if (m.contains('wav') || m.contains('x-wav') || m.contains('pcm')) {
      return 'WAV';
    }
    if (m.contains('aac') || m.contains('mp4a') || m.contains('m4a')) {
      return 'AAC';
    }
    // Fall back to the file extension when the mime is generic.
    final ext = (path ?? '').toLowerCase();
    if (ext.endsWith('.flac')) return 'FLAC';
    if (ext.endsWith('.m4a') || ext.endsWith('.aac')) return 'AAC';
    if (ext.endsWith('.mp3')) return 'MP3';
    if (ext.endsWith('.opus')) return 'OPUS';
    if (ext.endsWith('.wav')) return 'WAV';
    if (ext.endsWith('.ogg')) return 'OGG';
    return mime.isEmpty ? 'AUDIO' : mime.split('/').last.toUpperCase();
  }
}
