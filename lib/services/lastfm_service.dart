import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Last.fm scrobbling integration.
class LastFmService {
  static final LastFmService instance = LastFmService._();
  LastFmService._();

  static const String _apiKey = 'YOUR_LASTFM_API_KEY';
  static const String _apiSecret = 'YOUR_LASTFM_API_SECRET';
  static const String _baseUrl = 'https://ws.audioscrobbler.com/2.0/';

  String? _sessionKey;
  String? _username;
  bool _isEnabled = false;

  bool get isEnabled => _isEnabled;
  String? get username => _username;

  /// Initialize from saved preferences
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionKey = prefs.getString('lastfm_session_key');
    _username = prefs.getString('lastfm_username');
    _isEnabled = prefs.getBool('lastfm_enabled') ?? false;
  }

  /// Enable/disable scrobbling
  Future<void> setEnabled(bool value) async {
    _isEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('lastfm_enabled', value);
  }

  /// Authenticate with Last.fm (web-based auth flow)
  Future<bool> authenticate() async {
    // Step 1: Get a request token
    final token = await _getToken();
    if (token == null) return false;

    // Step 2: User must authorize at this URL
    final authUrl =
        'https://www.last.fm/api/auth/?api_key=$_apiKey&token=$token';
    // In production: open authUrl in browser, capture callback

    // Step 3: Get session key (simulated here)
    _sessionKey = await _getSession(token);
    if (_sessionKey != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastfm_session_key', _sessionKey!);
      _isEnabled = true;
      await prefs.setBool('lastfm_enabled', true);
      return true;
    }
    return false;
  }

  /// Get a request token
  Future<String?> _getToken() async {
    try {
      final sig = _sign({'method': 'auth.getToken'});
      final url = '$_baseUrl?method=auth.getToken&api_key=$_apiKey&api_sig=$sig&format=json';
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        return data['token'] as String?;
      }
    } catch (_) {}
    return null;
  }

  /// Exchange token for session key
  Future<String?> _getSession(String token) async {
    try {
      final sig = _sign({'method': 'auth.getSession', 'token': token});
      final url =
          '$_baseUrl?method=auth.getSession&api_key=$_apiKey&token=$token&api_sig=$sig&format=json';
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        final session = data['session'];
        _username = session['name'] as String?;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('lastfm_username', _username ?? '');
        return session['key'] as String?;
      }
    } catch (_) {}
    return null;
  }

  /// Scrobble a track ("now playing" + submit when done)
  Future<void> scrobble({
    required String artist,
    required String track,
    String? album,
    int? durationSeconds,
  }) async {
    if (!_isEnabled || _sessionKey == null) return;

    final params = <String, String>{
      'method': 'track.updateNowPlaying',
      'artist': artist,
      'track': track,
      'api_key': _apiKey,
      'sk': _sessionKey!,
    };
    if (album != null) params['album'] = album;
    if (durationSeconds != null) {
      params['duration'] = durationSeconds.toString();
    }
    params['api_sig'] = _sign(params);

    try {
      await http.post(Uri.parse(_baseUrl), body: params);
    } catch (_) {
      // Silently fail — scrobbling is best-effort
    }
  }

  /// Submit a completed scrobble
  Future<void> submitScrobble({
    required String artist,
    required String track,
    String? album,
    int? durationSeconds,
  }) async {
    if (!_isEnabled || _sessionKey == null) return;

    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final params = <String, String>{
      'method': 'track.scrobble',
      'artist[0]': artist,
      'track[0]': track,
      'timestamp[0]': timestamp.toString(),
      'api_key': _apiKey,
      'sk': _sessionKey!,
    };
    if (album != null) params['album[0]'] = album;
    if (durationSeconds != null) {
      params['duration[0]'] = durationSeconds.toString();
    }
    params['api_sig'] = _sign(params);

    try {
      await http.post(Uri.parse(_baseUrl), body: params);
    } catch (_) {
      // Silently fail
    }
  }

  /// Love/unlove a track on Last.fm
  Future<void> toggleLove({
    required String artist,
    required String track,
    required bool love,
  }) async {
    if (!_isEnabled || _sessionKey == null) return;

    final params = <String, String>{
      'method': love ? 'track.love' : 'track.unlove',
      'artist': artist,
      'track': track,
      'api_key': _apiKey,
      'sk': _sessionKey!,
    };
    params['api_sig'] = _sign(params);

    try {
      await http.post(Uri.parse(_baseUrl), body: params);
    } catch (_) {}
  }

  /// Sign parameters with MD5 as required by Last.fm API
  String _sign(Map<String, String> params) {
    final sortedKeys = params.keys.toList()..sort();
    final sb = StringBuffer();
    for (final key in sortedKeys) {
      if (key != 'api_sig') {
        sb.write('$key${params[key]}');
      }
    }
    sb.write(_apiSecret);
    return md5.convert(utf8.encode(sb.toString())).toString();
  }

  /// Logout
  Future<void> logout() async {
    _sessionKey = null;
    _username = null;
    _isEnabled = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('lastfm_session_key');
    await prefs.remove('lastfm_username');
    await prefs.setBool('lastfm_enabled', false);
  }
}
