/// Models for the YouTube Music integration. Everything here is parsed out of
/// innertube JSON by [Innertube]'s tolerant extractors — fields are nullable
/// where YT Music omits them per-surface.
library;

import '../models.dart';

enum YtItemKind { song, video, album, playlist, artist, channel }

/// One entity from any YT Music surface (home shelf, search result, playlist
/// row, channel grid…). Exactly one of [videoId]/[browseId]/[playlistId] is
/// the primary handle depending on [kind].
class YtMusicItem {
  final YtItemKind kind;
  final String? videoId; // songs / videos
  final String? browseId; // albums (MPRE…), artists/channels (UC…)
  final String? playlistId; // playlists / mixes (VL-stripped)
  final String title;
  final String subtitle; // artist · album · views, as YT renders it
  final String? thumbnail; // largest available
  final int? durationSec;

  const YtMusicItem({
    required this.kind,
    this.videoId,
    this.browseId,
    this.playlistId,
    required this.title,
    this.subtitle = '',
    this.thumbnail,
    this.durationSec,
  });

  /// Playable [Track] for songs/videos. YT tracks carry no sourceUri — the
  /// player resolves a stream lazily (see YtStreamResolver).
  Track? toTrack() {
    final id = videoId;
    if (id == null) return null;
    return Track(
      id: 'yt:$id',
      title: title,
      artist: artistFromSubtitle(subtitle),
      album: null,
      filePath: '',
      duration: (durationSec ?? 0).toDouble(),
      // Some surfaces (album pages, certain A/B layouts) omit per-track
      // thumbnails; every video has a ytimg still, so no YT track is ever
      // art-less in the player.
      artUri: thumbnail ?? 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
    );
  }

  /// Pull the artist out of a YT Music subtitle. These come as ` · `-joined
  /// segments that sometimes lead with a type word ("Song", "Video") and
  /// trail with view counts / durations, e.g. "Song · Arijit Singh · 394M
  /// plays" or "Arijit Singh · 2 States". Returns the first segment that
  /// actually looks like an artist.
  static String artistFromSubtitle(String subtitle) {
    if (subtitle.isEmpty) return 'YouTube';
    const typeWords = {
      'song', 'video', 'artist', 'album', 'single', 'ep', 'playlist'
    };
    final segs = subtitle.split(' · ').map((s) => s.trim()).toList();
    for (final s in segs) {
      if (s.isEmpty) continue;
      final low = s.toLowerCase();
      if (typeWords.contains(low)) continue; // skip the type label
      // Skip trailing metadata like "394M plays" / "3:21" / "2020".
      if (RegExp(r'plays$|views$|^\d[\d.,]*[km]?$|^\d+:\d+$').hasMatch(low)) {
        continue;
      }
      return s;
    }
    return segs.first;
  }
}

/// A titled row of items — a home-feed carousel, a search section, a channel
/// shelf. [continuation] pages the surface it came from when non-null.
class YtShelf {
  final String title;
  final String? subtitle; // e.g. "START RADIO AGAIN" strapline
  final List<YtMusicItem> items;
  const YtShelf({required this.title, this.subtitle, required this.items});
}

/// A resolved, directly playable audio stream for a video.
class YtStream {
  final String url;
  final String mime; // e.g. audio/mp4; codecs="mp4a.40.2"
  final int? contentLength; // bytes, when YT reports it
  final int bitrate;
  final DateTime expiresAt; // stream URLs die after ~6h; refresh past this
  // googlevideo stalls/times out connections whose user-agent doesn't match
  // the client that minted the URL — every fetch of [url] must send this UA.
  final String userAgent;
  const YtStream({
    required this.url,
    required this.mime,
    this.contentLength,
    required this.bitrate,
    required this.expiresAt,
    required this.userAgent,
  });

  bool get fresh => DateTime.now().isBefore(expiresAt);

  /// Content type without codec suffix, for players/proxies.
  String get contentType {
    final i = mime.indexOf(';');
    return i < 0 ? mime : mime.substring(0, i);
  }
}
