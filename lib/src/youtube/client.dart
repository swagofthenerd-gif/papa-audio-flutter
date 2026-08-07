import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

/// InnerTube API client for YouTube.
///
/// Extracts the latest API key and client version from YouTube's web player
/// JS and talks directly to the InnerTube endpoints. This is the same approach
/// used by yt-dlp, NewPipe, and Invidious.
class YouTubeInnerTubeClient {
  static const _baseUrl = 'https://www.youtube.com/youtubei/v1';
  static const _keyRegex =
      r'(?:INNERTUBE_API_KEY|innertubeApiKey)\s*[:=]\s*"([^"]+)"';
  static const _clientVersionRegex =
      r'(?:INNERTUBE_CLIENT_VERSION|innertubeClientVersion)\s*[:=]\s*"([^"]+)"';

  final http.Client _http;
  String? _apiKey;
  String? _clientVersion;
  DateTime _lastKeyFetch = DateTime.fromMillisecondsSinceEpoch(0);
  static const _keyTtl = Duration(hours: 6);

  /// Android client context sent with every InnerTube request.
  static const _clientContext = {
    'client': {
      'hl': 'en',
      'gl': 'US',
      'clientName': 'ANDROID',
      'clientVersion': '19.09.37',
      'androidSdkVersion': 33,
      'userAgent':
          'com.google.android.youtube/19.09.37 (Linux; U; Android 13) gzip',
    },
  };

  YouTubeInnerTubeClient({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  // ── API key management ──────────────────────────────────────────

  Future<String> _ensureApiKey() async {
    if (_apiKey != null && DateTime.now().difference(_lastKeyFetch) < _keyTtl) {
      return _apiKey!;
    }
    await _refreshKey();
    return _apiKey!;
  }

  Future<void> _refreshKey() async {
    // Multiple fallback patterns for extracting the key.
    const patterns = [
      _keyRegex,
      r'"innertubeApiKey"\s*:\s*"([^"]+)"',
      r'INNERTUBE_API_KEY\s*=\s*"([^"]+)"',
      r'ytcfg\.set\s*\(\s*\{\s*"INNERTUBE_API_KEY"\s*:\s*"([^"]+)"',
    ];

    // Try the main player JS URL first, then fall back to the base page.
    final urls = [
      'https://www.youtube.com/iframe_api',
      'https://www.youtube.com/sw.js',
      'https://www.youtube.com/',
    ];

    for (final url in urls) {
      try {
        final resp = await _http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 8));
        if (resp.statusCode != 200) continue;
        final body = resp.body;

        for (final pattern in patterns) {
          final match = RegExp(pattern).firstMatch(body);
          if (match != null) {
            _apiKey = match.group(1)!;
            _lastKeyFetch = DateTime.now();

            // Also try to extract client version
            for (final vp in [
              _clientVersionRegex,
              r'"clientVersion"\s*:\s*"([^"]+)"',
            ]) {
              final vm = RegExp(vp).firstMatch(body);
              if (vm != null) {
                _clientVersion = vm.group(1);
                break;
              }
            }
            return;
          }
        }
      } catch (_) {
        continue;
      }
    }
    // If all extraction fails, use a known working fallback.
    if (_apiKey == null) {
      _apiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
    }
  }

  // ── Core InnerTube request ──────────────────────────────────────

  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, dynamic> body, {
    String? apiKey,
  }) async {
    final key = apiKey ?? await _ensureApiKey();
    final url = Uri.parse('$_baseUrl/$endpoint?key=$key');
    final mergedBody = {
      ..._clientContext,
      ...body,
    };
    final resp = await _http
        .post(url,
            headers: {
              'Content-Type': 'application/json',
              'User-Agent':
                  'com.google.android.youtube/19.09.37 (Linux; U; Android 13) gzip',
              'Accept-Language': 'en-US,en;q=0.9',
            },
            body: jsonEncode(mergedBody))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      // If key is stale, refresh and retry once.
      _apiKey = null;
      final newKey = await _ensureApiKey();
      final retryUrl = Uri.parse('$_baseUrl/$endpoint?key=$newKey');
      final retryResp = await _http
          .post(retryUrl,
              headers: {
                'Content-Type': 'application/json',
                'User-Agent':
                    'com.google.android.youtube/19.09.37 (Linux; U; Android 13) gzip',
              },
              body: jsonEncode(mergedBody))
          .timeout(const Duration(seconds: 15));
      if (retryResp.statusCode != 200) {
        throw Exception(
            'YouTube API returned ${retryResp.statusCode}: ${retryResp.body}');
      }
      return jsonDecode(retryResp.body);
    }
    return jsonDecode(resp.body);
  }

  // ── Public API ──────────────────────────────────────────────────

  /// Search YouTube. Type can be empty, "video", "playlist", or "channel".
  Future<YouTubeSearchResult> search(String query,
      {String type = '', String? continuationToken}) async {
    Map<String, dynamic> body;
    if (continuationToken != null) {
      body = {'continuation': continuationToken};
    } else {
      body = {
        'query': query,
        if (type.isNotEmpty) 'params': _searchParams(type),
      };
    }
    final data = await _post('search', body);
    return YouTubeSearchResult.fromJson(data);
  }

  /// Get audio stream URLs for a video.
  Future<List<YouTubeAudioFormat>> getAudioFormats(String videoId) async {
    final data = await _post('player', {'videoId': videoId});
    final formats = (data['streamingData']?['adaptiveFormats'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    return formats
        .where((f) => (f['mimeType'] as String?)?.contains('audio') == true)
        .map(YouTubeAudioFormat.fromJson)
        .toList()
      ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
  }

  /// Get video details.
  Future<YouTubeVideo?> getVideoDetails(String videoId) async {
    final data = await _post('player', {'videoId': videoId});
    final details = data['videoDetails'];
    if (details == null) return null;
    return YouTubeVideo(
      videoId: videoId,
      title: details['title'] ?? '',
      author: details['author'] ?? '',
      authorId: details['channelId'] ?? '',
      thumbnailUrl: (details['thumbnail']?['thumbnails'] as List?)
              ?.lastOrNull?['url'] ??
          '',
      lengthSeconds: int.tryParse('${details['lengthSeconds'] ?? 0}') ?? 0,
      viewCount: int.tryParse('${details['viewCount'] ?? 0}') ?? 0,
    );
  }

  /// Get comments for a video.
  Future<List<YouTubeComment>> getComments(String videoId,
      {String? continuationToken}) async {
    final body = <String, dynamic>{
      'videoId': videoId,
      if (continuationToken != null) 'continuation': continuationToken,
    };
    final data = await _post('next', body);
    final items = (data['contents']
                ?['twoColumnWatchNextResults']
            ?['results']?['results']?['contents'] as List?) ??
        [];
    final comments = <YouTubeComment>[];
    for (final item in items) {
      final thread = item['itemSectionRenderer']?['contents']
          ?.firstOrNull?['commentThreadRenderer'];
      final comment = thread?['comment']?['commentRenderer'];
      if (comment != null) {
        comments.add(YouTubeComment.fromJson(comment));
      }
    }
    return comments;
  }

  /// Get related videos.
  Future<List<YouTubeVideo>> getRelated(String videoId) async {
    final data = await _post('next', {'videoId': videoId});
    final items = (data['contents']
                ?['twoColumnWatchNextResults']
            ?['secondaryResults']?['secondaryResults']?['results'] as List?) ??
        [];
    final videos = <YouTubeVideo>[];
    for (final item in items) {
      final compact = item['compactVideoRenderer'];
      if (compact != null) {
        videos.add(YouTubeVideo.fromJson(compact));
      }
    }
    return videos;
  }

  /// Get channel details.
  Future<YouTubeChannel?> getChannel(String channelId) async {
    final data = await _post('browse', {'browseId': channelId});
    final header = data['header']?['c4TabbedHeaderRenderer'];
    if (header == null) return null;
    return YouTubeChannel(
      channelId: channelId,
      name: header['title'] ?? '',
      thumbnailUrl:
          (header['avatar']?['thumbnails'] as List?)?.lastOrNull?['url'] ?? '',
      subscriberCount:
          header['subscriberCountText']?['simpleText'] ?? '',
    );
  }

  /// Get channel videos.
  Future<List<YouTubeVideo>> getChannelVideos(String channelId) async {
    final data = await _post('browse', {
      'browseId': channelId,
      'params': 'EgZ2aWRlb3PyBgQKAjoA',
    });
    final tabs = data['contents']?['twoColumnBrowseResultsRenderer']
            ?['tabs'] as List? ??
        [];
    for (final tab in tabs) {
      final items = tab['tabRenderer']?['content']?['richGridRenderer']
              ?['contents'] as List? ??
          [];
      final videos = <YouTubeVideo>[];
      for (final item in items) {
        final renderer = item['richItemRenderer']?['content']
            ?['videoRenderer'];
        if (renderer != null) {
          videos.add(YouTubeVideo.fromJson(renderer));
        }
      }
      if (videos.isNotEmpty) return videos;
    }
    return [];
  }

  /// Get playlist details with video list.
  Future<({YouTubePlaylist playlist, List<YouTubeVideo> videos})?> getPlaylist(
      String playlistId) async {
    final data = await _post('browse', {'browseId': 'VL$playlistId'});
    final header = data['header']?['playlistHeaderRenderer'];
    if (header == null) return null;

    final playlist = YouTubePlaylist(
      playlistId: playlistId,
      title: header['title']?['simpleText'] ?? header['title']?['runs']
              ?.firstOrNull?['text'] ??
          '',
      author: header['ownerText']?['runs']?.firstOrNull?['text'] ?? '',
      thumbnailUrl: (header['playlistThumbnail']?['thumbnail']?['thumbnails']
                  as List?)
              ?.lastOrNull?['url'] ??
          '',
      videoCount: int.tryParse('${header['numVideosText']?['runs']
                  ?.firstOrNull?['text'] ?? '0'}'
              .replaceAll(RegExp(r'[^0-9]'), '')) ??
          0,
    );
    final videos = <YouTubeVideo>[];
    final contents = data['contents']?['twoColumnBrowseResultsRenderer']
            ?['secondaryContents']?['playlistVideoListRenderer']
            ?['contents'] as List? ??
        [];
    for (final item in contents) {
      final renderer = item['playlistVideoRenderer'];
      if (renderer != null) {
        videos.add(YouTubeVideo.fromJson(renderer));
      }
    }
    return (playlist: playlist, videos: videos);
  }

  /// Search params: video = EgIQAQ%3D%3D, playlist = EgIQAw%3D%3D,
  /// channel = EgIQAg%3D%3D
  static String _searchParams(String type) {
    switch (type) {
      case 'video':
        return 'EgIQAQ%3D%3D';
      case 'channel':
        return 'EgIQAg%3D%3D';
      case 'playlist':
        return 'EgIQAw%3D%3D';
      default:
        return '';
    }
  }

  void dispose() => _http.close();
}

/// Production YouTube service — search, stream, download, comments.
class YouTubeService {
  final YouTubeInnerTubeClient client;

  YouTubeService({YouTubeInnerTubeClient? client})
      : client = client ?? YouTubeInnerTubeClient();

  // ── Search ──────────────────────────────────────────────────────

  Future<YouTubeSearchResult> search(String query) => client.search(query);

  Future<List<YouTubeVideo>> searchVideos(String query) async {
    final result = await client.search(query, type: 'video');
    return result.videos;
  }

  // ── Audio streaming ─────────────────────────────────────────────

  /// Get the best audio stream URL for a video.
  Future<String?> getAudioStreamUrl(String videoId) async {
    try {
      final formats = await client.getAudioFormats(videoId);
      if (formats.isEmpty) return null;
      // Prefer opus > 128kbps, then highest bitrate.
      final opus = formats.where((f) => f.mimeType.contains('opus'));
      if (opus.isNotEmpty) return opus.first.url;
      return formats.first.url;
    } catch (_) {
      return null;
    }
  }

  /// Get video details for a videoId.
  Future<YouTubeVideo?> getVideoDetails(String videoId) =>
      client.getVideoDetails(videoId);

  /// Get related videos.
  Future<List<YouTubeVideo>> getRelated(String videoId) =>
      client.getRelated(videoId);

  /// Get comments.
  Future<List<YouTubeComment>> getComments(String videoId) =>
      client.getComments(videoId);

  /// Get channel info.
  Future<YouTubeChannel?> getChannel(String channelId) =>
      client.getChannel(channelId);

  /// Get channel videos.
  Future<List<YouTubeVideo>> getChannelVideos(String channelId) =>
      client.getChannelVideos(channelId);

  void dispose() => client.dispose();
}
