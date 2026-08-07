import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import '../models.dart';

/// Subsonic / OpenSubsonic API client.
class SubsonicService {
  String? _serverUrl;
  String? _username;
  String? _password;
  final http.Client _http = http.Client();

  bool get isConnected => _serverUrl != null && _username != null;

  Future<void> loadCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    _serverUrl = prefs.getString('subsonic_url');
    _username = prefs.getString('subsonic_user');
    _password = prefs.getString('subsonic_pass');
  }

  Future<bool> connect(String serverUrl, String username,
      String password) async {
    try {
      final url = _buildUrl('ping', {});
      final resp = await _http.get(url).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return false;
      final xml = XmlDocument.parse(resp.body);
      if (xml.findAllElements('error').isNotEmpty) return false;

      _serverUrl = serverUrl;
      _username = username;
      _password = password;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('subsonic_url', serverUrl);
      await prefs.setString('subsonic_user', username);
      await prefs.setString('subsonic_pass', password);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<Album>> getAlbums({int limit = 50, int offset = 0}) async {
    if (!isConnected) return [];
    try {
      final resp = await _http.get(_buildUrl('getAlbumList2', {
        'type': 'alphabeticalByName',
        'size': limit.toString(),
        'offset': offset.toString(),
      }));
      final xml = XmlDocument.parse(resp.body);
      return xml.findAllElements('album').map((e) {
        return Album(
          name: e.getAttribute('name') ?? e.getAttribute('title') ?? '',
          artist: e.getAttribute('artist') ?? '',
          artworkUrl: e.getAttribute('coverArt') != null
              ? _buildUrlStr('getCoverArt', {
                  'id': e.getAttribute('coverArt')!,
                  'size': '300',
                })
              : null,
          trackCount:
              int.tryParse(e.getAttribute('songCount') ?? '0') ?? 0,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Track>> getAlbumTracks(String albumId) async {
    if (!isConnected) return [];
    try {
      final resp = await _http.get(_buildUrl('getAlbum', {'id': albumId}));
      final xml = XmlDocument.parse(resp.body);
      return xml.findAllElements('song').map((e) {
        final id = e.getAttribute('id') ?? '';
        return Track(
          path: id,
          title: e.getAttribute('title') ?? '',
          artist: e.getAttribute('artist') ?? '',
          album: e.getAttribute('album') ?? '',
          duration: int.tryParse(e.getAttribute('duration') ?? '0') ?? 0,
          source: 'subsonic',
          remoteUrl: _buildUrlStr('stream', {'id': id}),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  String getStreamUrl(String trackId) =>
      _buildUrlStr('stream', {'id': trackId});

  String getArtworkUrl(String coverArtId) =>
      _buildUrlStr('getCoverArt', {'id': coverArtId, 'size': '300'});

  Future<List<Track>> search(String query) async {
    if (!isConnected) return [];
    try {
      final resp = await _http.get(_buildUrl('search3', {
        'query': query,
        'songCount': '30',
      }));
      final xml = XmlDocument.parse(resp.body);
      return xml.findAllElements('song').map((e) {
        final id = e.getAttribute('id') ?? '';
        return Track(
          path: id,
          title: e.getAttribute('title') ?? '',
          artist: e.getAttribute('artist') ?? '',
          album: e.getAttribute('album') ?? '',
          duration: int.tryParse(e.getAttribute('duration') ?? '0') ?? 0,
          source: 'subsonic',
          remoteUrl: _buildUrlStr('stream', {'id': id}),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> disconnect() async {
    _serverUrl = null;
    _username = null;
    _password = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('subsonic_url');
    await prefs.remove('subsonic_user');
    await prefs.remove('subsonic_pass');
  }

  Uri _buildUrl(String endpoint, Map<String, String> params) {
    final salt = Random().nextInt(999999).toString().padLeft(6, '0');
    final token =
        md5.convert(utf8.encode('$_password$salt')).toString();
    final allParams = {
      'u': _username ?? '',
      't': token,
      's': salt,
      'v': '1.16.1',
      'c': 'PapaAudio',
      'f': 'json',
      ...params,
    };
    return Uri.parse('$_serverUrl/rest/$endpoint')
        .replace(queryParameters: allParams);
  }

  String _buildUrlStr(String endpoint, Map<String, String> params) {
    return _buildUrl(endpoint, params).toString();
  }

  void dispose() => _http.close();
}
