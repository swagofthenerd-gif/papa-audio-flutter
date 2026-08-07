import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

/// Jellyfin API client.
class JellyfinService {
  String? _serverUrl;
  String? _apiKey;
  String? _userId;
  final http.Client _http = http.Client();

  bool get isConnected => _serverUrl != null && _apiKey != null;

  Future<void> loadCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    _serverUrl = prefs.getString('jellyfin_url');
    _apiKey = prefs.getString('jellyfin_key');
    _userId = prefs.getString('jellyfin_user');
  }

  Future<bool> authenticate(String serverUrl, String username,
      String password) async {
    try {
      final authHeader = 'MediaBrowser '
          'Client="PapaAudio", '
          'Device="Android", '
          'DeviceId="${await _deviceId()}", '
          'Version="1.0.0"';
      final resp = await _http.post(
        Uri.parse('$serverUrl/Users/AuthenticateByName'),
        headers: {
          'Content-Type': 'application/json',
          'X-Emby-Authorization': authHeader,
        },
        body: jsonEncode({'Username': username, 'Pw': password}),
      );
      if (resp.statusCode != 200) return false;
      final data = jsonDecode(resp.body);
      _serverUrl = serverUrl;
      _apiKey = data['AccessToken'];
      _userId = data['User']['Id'];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jellyfin_url', serverUrl);
      await prefs.setString('jellyfin_key', _apiKey!);
      await prefs.setString('jellyfin_user', _userId!);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<Album>> getAlbums({int limit = 50, int offset = 0}) async {
    if (!isConnected) return [];
    try {
      final resp = await _http.get(
        Uri.parse(
            '$_serverUrl/Users/$_userId/Items?IncludeItemTypes=MusicAlbum'
            '&SortBy=SortName&SortOrder=Ascending'
            '&Limit=$limit&StartIndex=$offset'),
        headers: _headers(),
      );
      final data = jsonDecode(resp.body);
      return (data['Items'] as List?)
              ?.map((j) => _albumFromJson(j))
              .toList() ??
          [];
    } catch (_) {
      return [];
    }
  }

  Future<List<Track>> getAlbumTracks(String albumId) async {
    if (!isConnected) return [];
    try {
      final resp = await _http.get(
        Uri.parse('$_serverUrl/Users/$_userId/Items'
            '?ParentId=$albumId&IncludeItemTypes=Audio'
            '&SortBy=IndexNumber&SortOrder=Ascending'),
        headers: _headers(),
      );
      final data = jsonDecode(resp.body);
      return (data['Items'] as List?)
              ?.map((j) => _trackFromJson(j))
              .toList() ??
          [];
    } catch (_) {
      return [];
    }
  }

  String getStreamUrl(String itemId) =>
      '$_serverUrl/Audio/$itemId/stream?api_key=$_apiKey';

  String getArtworkUrl(String itemId) =>
      '$_serverUrl/Items/$itemId/Images/Primary?api_key=$_apiKey';

  Future<List<Track>> search(String query) async {
    if (!isConnected) return [];
    try {
      final resp = await _http.get(
        Uri.parse('$_serverUrl/Users/$_userId/Items'
            '?SearchTerm=$query&IncludeItemTypes=Audio'
            '&Recursive=true&Limit=30'),
        headers: _headers(),
      );
      final data = jsonDecode(resp.body);
      return (data['Items'] as List?)
              ?.map((j) => _trackFromJson(j))
              .toList() ??
          [];
    } catch (_) {
      return [];
    }
  }

  Future<void> disconnect() async {
    _serverUrl = null;
    _apiKey = null;
    _userId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jellyfin_url');
    await prefs.remove('jellyfin_key');
    await prefs.remove('jellyfin_user');
  }

  Map<String, String> _headers() => {
        'X-Emby-Authorization': 'MediaBrowser '
            'Client="PapaAudio", '
            'Device="Android", '
            'DeviceId="${_deviceIdSync()}", '
            'Version="1.0.0", '
            'Token="$_apiKey"',
      };

  Track _trackFromJson(Map<String, dynamic> j) => Track(
        path: j['Id'],
        title: j['Name'] ?? '',
        artist: j['Artists']?.firstOrNull ?? j['AlbumArtist'] ?? '',
        album: j['Album'] ?? '',
        duration: (j['RunTimeTicks'] ?? 0) ~/ 10000000,
        source: 'jellyfin',
        remoteUrl: getStreamUrl(j['Id']),
      );

  Album _albumFromJson(Map<String, dynamic> j) => Album(
        name: j['Name'] ?? '',
        artist: j['AlbumArtist'] ?? '',
        artworkUrl: getArtworkUrl(j['Id']),
        trackCount: j['ChildCount'] ?? 0,
      );

  static Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('device_id');
    if (id == null) {
      id = DateTime.now().millisecondsSinceEpoch
          .toRadixString(36)
          .padLeft(12, '0');
      await prefs.setString('device_id', id);
    }
    return id;
  }

  static String _deviceIdSync() {
    // Best-effort sync fallback
    return 'papa_audio_001';
  }

  void dispose() => _http.close();
}
