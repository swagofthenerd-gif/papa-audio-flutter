import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';

/// Google account login for YouTube Music. Loads the real accounts.google.com
/// flow in a webview; once the user is signed in and music.youtube.com sets its
/// session cookies, we capture them (SAPISID et al) and hand them to [YtAuth].
///
/// No credentials touch our code — Google's own page collects them; we only
/// read the resulting cookies from the webview's cookie jar for our own origin.
class YtLoginScreen extends StatefulWidget {
  const YtLoginScreen({super.key});
  @override
  State<YtLoginScreen> createState() => _YtLoginScreenState();
}

class _YtLoginScreenState extends State<YtLoginScreen> {
  final _cookieManager = CookieManager.instance();
  bool _finishing = false;

  static final _loginUrl = WebUri(
      'https://accounts.google.com/ServiceLogin?service=youtube&continue=https://music.youtube.com/');

  Future<void> _tryCapture() async {
    if (_finishing) return;
    final cookies =
        await _cookieManager.getCookies(url: WebUri('https://music.youtube.com'));
    final map = <String, String>{
      for (final c in cookies) c.name: c.value.toString()
    };
    if (!map.containsKey('SAPISID') && !map.containsKey('__Secure-3PAPISID')) {
      return; // not signed in yet — keep the webview open
    }
    _finishing = true;
    if (!mounted) return;
    final s = context.read<AppState>();
    await s.ytAuth.setCookies(map);
    await s.yt.onAuthChanged();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: PA.background,
        title: const Text('Sign in to YouTube Music',
            style: TextStyle(fontSize: 17)),
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: _loginUrl),
        initialSettings: InAppWebViewSettings(
          // Some Google login checks reject non-desktop UAs; match innertube's.
          userAgent:
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
          javaScriptEnabled: true,
        ),
        onLoadStop: (controller, url) async {
          // Once redirected back to music.youtube.com, cookies should be set.
          if (url != null && url.host.contains('music.youtube.com')) {
            await _tryCapture();
          }
        },
      ),
    );
  }
}
