import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import '../models.dart';

/// WebDAV client for accessing music on Nextcloud, ownCloud, etc.
class WebDavService {
  String? _serverUrl;
  String? _username;
  String? _password;
  final http.Client _http = http.Client();

  bool get isConnected => _serverUrl != null;

  Future<void> loadCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    _serverUrl = prefs.getString('webdav_url');
    _username = prefs.getString('webdav_user');
    _password = prefs.getString('webdav_pass');
  }

  Future<bool> connect(String serverUrl, String username,
      String password) async {
    try {
      _serverUrl = serverUrl;
      _username = username;
      _password = password;
      // Test connection with a PROPFIND
      final resp = await _propfind('');
      final success = resp.statusCode == 207;
      if (success) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('webdav_url', serverUrl);
        await prefs.setString('webdav_user', username);
        await prefs.setString('webdav_pass', password);
      }
      return success;
    } catch (_) {
      return false;
    }
  }

  Future<List<Album>> getAlbums() async {
    if (!isConnected) return [];
    try {
      final resp = await _propfind('');
      if (resp.statusCode != 207) return [];
      final xml = XmlDocument.parse(resp.body);
      final albums = <String, List<Track>>{};
      for (final response in xml.findAllElements('{DAV:}response')) {
        final href = response
            .findAllElements('{DAV:}href')
            .firstOrNull
            ?.innerText;
        final contentType = response
            .findAllElements('{DAV:}getcontenttype')
            .firstOrNull
            ?.innerText;
        if (href == null || contentType == null) continue;

        if (contentType.startsWith('audio/') ||
            _audioExts.any((e) => href.toLowerCase().endsWith(e))) {
          final parts = href.split('/');
          final fileName = parts.lastOrNull ?? href;
          final albumName = parts.length > 2 ? parts[parts.length - 2] : 'Root';
          albums.putIfAbsent(albumName, () => []);
          albums[albumName]!.add(Track(
            path: href,
            title: fileName,
            artist: '',
            album: albumName,
            source: 'webdav',
            remoteUrl: '$_serverUrl$href',
          ));
        }
      }
      return albums.entries.map((e) {
        return Album(
          name: e.key,
          artist: '',
          trackCount: e.value.length,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  String getStreamUrl(String path) => '$_serverUrl$path';

  Future<void> disconnect() async {
    _serverUrl = null;
    _username = null;
    _password = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('webdav_url');
    await prefs.remove('webdav_user');
    await prefs.remove('webdav_pass');
  }

  Future<http.Response> _propfind(String path) async {
    final uri = Uri.parse('$_serverUrl$path');
    final request = http.Request('PROPFIND', uri);
    request.headers['Authorization'] = _basicAuth();
    request.headers['Depth'] = '1';
    request.body = '''<?xml version="1.0" encoding="utf-8"?>
      <d:propfind xmlns:d="DAV:">
        <d:prop>
          <d:getcontenttype/>
          <d:getcontentlength/>
          <d:resourcetype/>
        </d:prop>
      </d:propfind>''';
    return _http.send(request).then((streamed) =>
        http.Response.fromStream(streamed));
  }

  String _basicAuth() {
    final credentials =
        base64Encode(utf8.encode('$_username:$_password'));
    return 'Basic $credentials';
  }

  static const _audioExts = [
    '.mp3', '.flac', '.wav', '.aac', '.ogg', '.opus', '.m4a', '.wma',
    '.alac', '.aiff', '.ape', '.dsf', '.dff', '.wv',
  ];

  void dispose() => _http.close();
}
