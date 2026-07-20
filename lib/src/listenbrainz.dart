import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

/// Submits listens to ListenBrainz (https://listenbrainz.org) — the
/// open-source, privacy-respecting scrobbling service. Needs the user's
/// personal token (from listenbrainz.org → Settings). Two submission types:
/// `playing_now` when a track starts, and `single` once it counts as a listen.
class ListenBrainzService {
  static const _endpoint = 'https://api.listenbrainz.org/1/submit-listens';

  final String Function() tokenProvider;
  final bool Function() enabledProvider;
  const ListenBrainzService(
      {required this.tokenProvider, required this.enabledProvider});

  bool get _ready => enabledProvider() && tokenProvider().trim().isNotEmpty;

  /// "Now playing" ping — no timestamp, replaced by the next track's ping.
  Future<void> playingNow(Track t) =>
      _submit('playing_now', t, listenedAt: null);

  /// A completed listen at [listenedAt] (epoch seconds).
  Future<void> listen(Track t, {DateTime? at}) => _submit('single', t,
      listenedAt: (at ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000);

  Future<void> _submit(String type, Track t, {int? listenedAt}) async {
    if (!_ready) return;
    // Skip tracks with no real artist metadata (e.g. bare YouTube uploads).
    if (t.title.trim().isEmpty) return;
    final meta = <String, dynamic>{
      'artist_name': t.artist,
      'track_name': t.title,
      if (t.album != null && t.album!.isNotEmpty) 'release_name': t.album,
      'additional_info': {
        'media_player': 'Papa Audio',
        'submission_client': 'Papa Audio',
      },
    };
    final payload = <String, dynamic>{'track_metadata': meta};
    if (listenedAt != null) payload['listened_at'] = listenedAt;
    try {
      final resp = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Authorization': 'Token ${tokenProvider().trim()}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'listen_type': type,
              'payload': [payload],
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        debugPrint('[listenbrainz] $type -> ${resp.statusCode} ${resp.body}');
      }
    } catch (e) {
      debugPrint('[listenbrainz] $type failed: $e');
    }
  }

  /// Validate a token — used by the settings screen's "Test" action.
  Future<bool> validate(String token) async {
    if (token.trim().isEmpty) return false;
    try {
      final resp = await http.get(
        Uri.parse('https://api.listenbrainz.org/1/validate-token'),
        headers: {'Authorization': 'Token ${token.trim()}'},
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return false;
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      return json['valid'] == true;
    } catch (_) {
      return false;
    }
  }
}
