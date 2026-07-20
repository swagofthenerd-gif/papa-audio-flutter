import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';

import '../db.dart';

/// YouTube account session: holds the cookies captured by the login webview
/// and builds the authenticated headers innertube requires.
///
/// Auth model (the same one every logged-in YT web client uses): requests to
/// music.youtube.com carry the account cookies plus an `Authorization:
/// SAPISIDHASH <ts>_<sha1(ts + " " + SAPISID + " " + origin)>` header derived
/// from the SAPISID cookie. No API key management, no OAuth screens — logging
/// in once in the webview is the whole setup.
class YtAuth extends ChangeNotifier {
  static const origin = 'https://music.youtube.com';
  static const _kvKey = 'yt_cookies';

  AppDatabase? _db;
  Map<String, String> _cookies = {};

  bool get signedIn => _cookies.containsKey('SAPISID');

  Future<void> init(AppDatabase db) async {
    _db = db;
    try {
      final raw = await db.getKv(_kvKey);
      if (raw != null && raw.isNotEmpty) _cookies = _parseCookieHeader(raw);
    } catch (_) {}
    notifyListeners();
  }

  /// Store the cookie header captured after a successful webview login.
  Future<void> setCookies(Map<String, String> cookies) async {
    _cookies = Map.of(cookies);
    try {
      await _db?.setKv(_kvKey, cookieHeader);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> signOut() async {
    _cookies = {};
    try {
      await _db?.setKv(_kvKey, '');
    } catch (_) {}
    notifyListeners();
  }

  String get cookieHeader =>
      _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  /// Headers for an authenticated innertube call. Anonymous when signed out —
  /// every surface still works, just not personalized.
  Map<String, String> headers() {
    final h = <String, String>{
      'content-type': 'application/json',
      'origin': origin,
      'referer': '$origin/',
      'user-agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
      'x-goog-authuser': '0',
      'x-origin': origin,
    };
    final sapisid = _cookies['SAPISID'] ?? _cookies['__Secure-3PAPISID'];
    if (sapisid != null) {
      final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final digest = crypto.sha1.convert('$ts $sapisid $origin'.codeUnits);
      h['authorization'] = 'SAPISIDHASH ${ts}_$digest';
      h['cookie'] = cookieHeader;
    }
    return h;
  }

  static Map<String, String> _parseCookieHeader(String raw) {
    final out = <String, String>{};
    for (final part in raw.split(';')) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      out[part.substring(0, i).trim()] = part.substring(i + 1).trim();
    }
    return out;
  }
}
