import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Client for the SponsorBlock API (https://sponsor.ajay.app).
///
/// Fetches crowd-sourced segment data to skip sponsored content,
/// intros, outros, self-promotion, and non-music parts of videos.
class SponsorBlockService {
  static const _baseUrl = 'https://sponsor.ajay.app/api';
  final http.Client _http = http.Client();

  /// Category constants matching the SponsorBlock API.
  static const categorySponsor = 'sponsor';
  static const categoryIntro = 'intro';
  static const categoryOutro = 'outro';
  static const categorySelfPromo = 'selfpromo';
  static const categoryInteraction = 'interaction';
  static const categoryMusicOfftopic = 'music_offtopic';

  /// Fetch segments for a YouTube video.
  /// [categories] is a list of category strings to include.
  Future<List<SponsorBlockSegment>> getSegments(
    String videoId, {
    List<String> categories = const [
      categorySponsor,
      categorySelfPromo,
      categoryMusicOfftopic,
    ],
  }) async {
    try {
      final catParam = categories.map((c) => '"$c"').join(',');
      final url = Uri.parse(
          '$_baseUrl/skipSegments?videoID=$videoId&categories=[$catParam]');
      final resp =
          await _http.get(url).timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return [];
      final List<dynamic> data = jsonDecode(resp.body);
      return data
          .map((j) => SponsorBlockSegment(
                startSeconds: (j['segment']?[0] as num?)?.toDouble() ?? 0,
                endSeconds: (j['segment']?[1] as num?)?.toDouble() ?? 0,
                category: j['category'] ?? '',
                actionType: j['actionType'] ?? 'skip',
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Get the total skip duration for a video.
  Future<Duration> totalSkipDuration(String videoId) async {
    final segments = await getSegments(videoId);
    double total = 0;
    for (final seg in segments) {
      if (seg.actionType == 'skip' || seg.actionType == 'auto_skip') {
        total += seg.endSeconds - seg.startSeconds;
      }
    }
    return Duration(seconds: total.round());
  }

  /// Check if a position falls within a skippable segment.
  /// Returns the segment to skip to, or null if not in a segment.
  Future<SponsorBlockSegment?> checkPosition(
      String videoId, double positionSeconds) async {
    final segments = await getSegments(videoId);
    for (final seg in segments) {
      if (positionSeconds >= seg.startSeconds &&
          positionSeconds < seg.endSeconds &&
          (seg.actionType == 'skip' || seg.actionType == 'auto_skip')) {
        return seg;
      }
    }
    return null;
  }

  void dispose() => _http.close();
}

class SponsorBlockSegment {
  final double startSeconds;
  final double endSeconds;
  final String category;
  final String actionType;

  const SponsorBlockSegment({
    required this.startSeconds,
    required this.endSeconds,
    required this.category,
    required this.actionType,
  });

  Duration get start => Duration(milliseconds: (startSeconds * 1000).round());
  Duration get end => Duration(milliseconds: (endSeconds * 1000).round());
  Duration get duration => end - start;

  String get categoryLabel {
    switch (category) {
      case 'sponsor':
        return 'Sponsor';
      case 'intro':
        return 'Intro';
      case 'outro':
        return 'Outro';
      case 'selfpromo':
        return 'Self-promo';
      case 'interaction':
        return 'Interaction';
      case 'music_offtopic':
        return 'Non-music';
      default:
        return category;
    }
  }
}
