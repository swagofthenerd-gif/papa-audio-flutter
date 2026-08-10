import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'settings.dart';

/// Last.fm scrobbling using the 2.0 API.  Now-playing updates are sent as soon
/// as a track starts; scrobbles are submitted once the listen threshold is
/// reached.  MD5-challenge auth keeps the password off the wire.
class LastFmService extends ChangeNotifier {
  final SettingsService _settings;
  String? _sessionKey;
  String? _username;

  String? get username => _username;
  bool get loggedIn => _sessionKey != null;

  /// Scrobbles queued while offline; flushed on next successful submit.
  final List<_PendingScrobble> _pending = [];
  Timer? _flushTimer;

  LastFmService(this._settings);

  // ── Auth ──

  Future<String> _apiSig(Map<String, String> params) {
    final raw = params.entries
        .map((e) => '${e.key}${e.value}')
        .toList()
      ..sort();
    final secret = _settings.lastFmSecret ?? '';
    return Future.value(md5.convert(utf8.encode('${raw.join()}$secret')).toString());
  }

  Future<http.Response> _post(Map<String, String> params) async {
    params['api_key'] = _settings.lastFmApiKey ?? '';
    params['api_sig'] = await _apiSig(params);
    params['format'] = 'json';
    return http.post(
      Uri.parse('https://ws.audioscrobbler.com/2.0/'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: params,
    ).timeout(const Duration(seconds: 10));
  }

  Future<bool> login(String username, String password) async {
    final r = await _post({
      'method': 'auth.getMobileSession',
      'username': username,
      'password': password,
    });
    if (r.statusCode != 200) return false;
    try {
      final j = jsonDecode(r.body);
      _sessionKey = j['session']['key'];
      _username = j['session']['name'];
      _settings.update(() {
        _settings.lastFmSessionKey = _sessionKey;
        _settings.lastFmUsername = _username;
      });
      notifyListeners();
      _flushPending();
      return true;
    } catch (_) {
      return false;
    }
  }

  void logout() {
    _sessionKey = null;
    _username = null;
    _settings.update(() {
      _settings.lastFmSessionKey = null;
      _settings.lastFmUsername = null;
    });
    notifyListeners();
  }

  void restoreSession() {
    _sessionKey = _settings.lastFmSessionKey;
    _username = _settings.lastFmUsername;
    notifyListeners();
    _flushPending();
  }

  // ── Scrobbling ──

  DateTime? _lastNowPlaying;

  Future<void> nowPlaying(Track track) async {
    if (_sessionKey == null) return;
    if (_lastNowPlaying != null &&
        _lastNowPlaying!.isAfter(
            DateTime.now().subtract(const Duration(seconds: 30)))) {
      return;
    }
    _lastNowPlaying = DateTime.now();
    try {
      await _post({
        'method': 'track.updateNowPlaying',
        'sk': _sessionKey!,
        'artist': track.artist,
        'track': track.title,
        if (track.album != null) 'album': track.album!,
        'duration': track.duration > 0 ? '${track.duration.round()}' : '',
      });
    } catch (_) {}
  }

  Future<void> scrobble(Track track, {int? timestamp}) async {
    if (_sessionKey == null) {
      _pending.add(_PendingScrobble(track: track, timestamp: timestamp));
      return;
    }
    try {
      final ts = timestamp ??
          DateTime.now().subtract(Duration(seconds: _settings.listenSeconds))
              .millisecondsSinceEpoch ~/
              1000;
      await _post({
        'method': 'track.scrobble',
        'sk': _sessionKey!,
        'artist[0]': track.artist,
        'track[0]': track.title,
        if (track.album != null) 'album[0]': track.album!,
        'timestamp[0]': '$ts',
      });
    } catch (_) {
      _pending.add(_PendingScrobble(track: track, timestamp: timestamp));
    }
  }

  Future<void> love(Track track) async {
    if (_sessionKey == null) return;
    try {
      await _post({
        'method': 'track.love',
        'sk': _sessionKey!,
        'artist': track.artist,
        'track': track.title,
      });
    } catch (_) {}
  }

  Future<void> unlove(Track track) async {
    if (_sessionKey == null) return;
    try {
      await _post({
        'method': 'track.unlove',
        'sk': _sessionKey!,
        'artist': track.artist,
        'track': track.title,
      });
    } catch (_) {}
  }

  void _flushPending() {
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(seconds: 3), () {
      if (_sessionKey == null || _pending.isEmpty) return;
      final batch = List.of(_pending);
      _pending.clear();
      for (final p in batch) {
        scrobble(p.track, timestamp: p.timestamp);
      }
    });
  }
}

class _PendingScrobble {
  final Track track;
  final int? timestamp;
  const _PendingScrobble({required this.track, this.timestamp});
}
