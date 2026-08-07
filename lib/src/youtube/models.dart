/// YouTube data models — matches InnerTube API responses.
class YouTubeVideo {
  final String videoId;
  final String title;
  final String author;
  final String authorId;
  final String thumbnailUrl;
  final int lengthSeconds;
  final int viewCount;

  const YouTubeVideo({
    required this.videoId,
    required this.title,
    required this.author,
    required this.authorId,
    required this.thumbnailUrl,
    required this.lengthSeconds,
    this.viewCount = 0,
  });

  factory YouTubeVideo.fromJson(Map<String, dynamic> json) {
    final vid = json['videoId'] ?? '';
    final thumbList = json['thumbnail']?['thumbnails'] as List? ?? [];
    final thumb = thumbList.isNotEmpty ? thumbList.last['url'] ?? '' : '';
    return YouTubeVideo(
      videoId: vid,
      title: (json['title']?['runs'] as List?)
              ?.map((r) => r['text'] ?? '')
              .join('') ??
          json['title']?['simpleText'] ??
          '',
      author: (json['ownerText']?['runs'] as List?)
              ?.map((r) => r['text'] ?? '')
              .join('') ??
          json['ownerText']?['simpleText'] ??
          '',
      authorId: (json['ownerText']?['runs'] as List?)
              ?.firstOrNull?['navigationEndpoint']
              ?['browseEndpoint']?['browseId'] ??
          '',
      thumbnailUrl: thumb,
      lengthSeconds: int.tryParse(
              '${json['lengthText']?['simpleText'] ?? '0:00'}'
                  .split(':')
                  .fold<int>(0, (s, p) => s * 60 + (int.tryParse(p) ?? 0))
                  .toString()) ??
          int.tryParse('${json['lengthSeconds'] ?? 0}') ??
          0,
      viewCount: int.tryParse('${json['viewCountText']?['simpleText'] ?? ''}'
              .replaceAll(RegExp(r'[^0-9]'), '')) ??
          0,
    );
  }

  String get durationFormatted {
    final m = lengthSeconds ~/ 60;
    final s = lengthSeconds % 60;
    return '${m}:${s.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'title': title,
        'author': author,
        'authorId': authorId,
        'thumbnailUrl': thumbnailUrl,
        'lengthSeconds': lengthSeconds,
        'viewCount': viewCount,
      };
}

class YouTubePlaylist {
  final String playlistId;
  final String title;
  final String author;
  final String thumbnailUrl;
  final int videoCount;

  const YouTubePlaylist({
    required this.playlistId,
    required this.title,
    required this.author,
    required this.thumbnailUrl,
    required this.videoCount,
  });

  factory YouTubePlaylist.fromJson(Map<String, dynamic> json) {
    return YouTubePlaylist(
      playlistId: json['playlistId'] ?? '',
      title: json['title']?['simpleText'] ?? '',
      author: json['shortBylineText']?['runs']?.firstOrNull?['text'] ?? '',
      thumbnailUrl: (json['thumbnails'] as List?)
                  ?.firstOrNull?['thumbnails']
                  ?.lastOrNull?['url'] ??
              '',
      videoCount: int.tryParse(
              '${json['videoCountText']?['runs']?.firstOrNull?['text'] ?? '0'}'
                  .replaceAll(RegExp(r'[^0-9]'), '')) ??
          0,
    );
  }
}

class YouTubeChannel {
  final String channelId;
  final String name;
  final String thumbnailUrl;
  final String subscriberCount;

  const YouTubeChannel({
    required this.channelId,
    required this.name,
    required this.thumbnailUrl,
    required this.subscriberCount,
  });

  factory YouTubeChannel.fromJson(Map<String, dynamic> json) {
    return YouTubeChannel(
      channelId: json['channelId'] ?? '',
      name: json['title']?['simpleText'] ?? '',
      thumbnailUrl: (json['thumbnail']?['thumbnails'] as List?)
              ?.lastOrNull?['url'] ??
          '',
      subscriberCount:
          json['subscriberCountText']?['simpleText'] ?? '',
    );
  }
}

/// Audio format extracted from YouTube player response.
class YouTubeAudioFormat {
  final String url;
  final int bitrate;
  final String mimeType;
  final int contentLength;

  const YouTubeAudioFormat({
    required this.url,
    required this.bitrate,
    required this.mimeType,
    this.contentLength = 0,
  });

  factory YouTubeAudioFormat.fromJson(Map<String, dynamic> json) {
    return YouTubeAudioFormat(
      url: json['url'] ?? '',
      bitrate: json['bitrate'] ?? 0,
      mimeType: json['mimeType'] ?? '',
      contentLength: int.tryParse('${json['contentLength'] ?? 0}') ?? 0,
    );
  }
}

/// Full YouTube search response.
class YouTubeSearchResult {
  final List<YouTubeVideo> videos;
  final List<YouTubePlaylist> playlists;
  final List<YouTubeChannel> channels;
  final String? continuationToken;

  const YouTubeSearchResult({
    this.videos = const [],
    this.playlists = const [],
    this.channels = const [],
    this.continuationToken,
  });

  factory YouTubeSearchResult.fromJson(Map<String, dynamic> json) {
    final contents = (json['contents'] as Map<String, dynamic>?) ??
        (json['onResponseReceivedCommands'] as List?)
                ?.firstOrNull?['appendContinuationItemsAction']
                ?['continuationItems'] ??
            [];
    final items = ((contents['twoColumnSearchResultsRenderer']
                    ?['primaryContents']
                ?['sectionListRenderer']?['contents'] as List?) ??
            [])
        .expand((s) =>
            (s['itemSectionRenderer']?['contents'] as List?) ?? <dynamic>[])
        .toList();
    final videos = <YouTubeVideo>[];
    final playlists = <YouTubePlaylist>[];
    final channels = <YouTubeChannel>[];
    for (final item in items) {
      if (item['videoRenderer'] != null) {
        videos.add(YouTubeVideo.fromJson(item['videoRenderer']));
      } else if (item['playlistRenderer'] != null) {
        playlists.add(YouTubePlaylist.fromJson(item['playlistRenderer']));
      } else if (item['channelRenderer'] != null) {
        channels.add(YouTubeChannel.fromJson(item['channelRenderer']));
      }
    }
    return YouTubeSearchResult(
      videos: videos,
      playlists: playlists,
      channels: channels,
      continuationToken: _findContinuation(contents),
    );
  }

  static String? _findContinuation(dynamic contents) {
    try {
      final items = (contents['twoColumnSearchResultsRenderer']
                  ?['primaryContents']
              ?['sectionListRenderer']?['contents'] as List?)
          ?.expand((s) => (s['itemSectionRenderer']?['contents'] as List?) ?? [])
          .toList();
      for (final item in items ?? []) {
        final token = item['continuationItemRenderer']
            ?['continuationEndpoint']?['continuationCommand']?['token'];
        if (token != null) return token;
      }
    } catch (_) {}
    return null;
  }
}

/// Comment on a YouTube video.
class YouTubeComment {
  final String author;
  final String authorThumbnail;
  final String text;
  final String publishedTime;
  final int likeCount;
  final int replyCount;

  const YouTubeComment({
    required this.author,
    required this.authorThumbnail,
    required this.text,
    required this.publishedTime,
    this.likeCount = 0,
    this.replyCount = 0,
  });

  factory YouTubeComment.fromJson(Map<String, dynamic> json) {
    return YouTubeComment(
      author: json['authorText']?['simpleText'] ?? '',
      authorThumbnail: (json['authorThumbnail']?['thumbnails'] as List?)
              ?.lastOrNull?['url'] ??
          '',
      text: (json['contentText']?['runs'] as List?)
              ?.map((r) => r['text'] ?? '')
              .join('') ??
          '',
      publishedTime: json['publishedTimeText']?['runs']
              ?.firstOrNull?['text'] ??
          '',
      likeCount:
          int.tryParse('${json['voteCount']?['simpleText'] ?? '0'}'
                  .replaceAll(RegExp(r'[^0-9]'), '')) ??
              0,
      replyCount: int.tryParse(
              '${json['replyCount'] ?? 0}'.replaceAll(RegExp(r'[^0-9]'), '')) ??
          0,
    );
  }
}
