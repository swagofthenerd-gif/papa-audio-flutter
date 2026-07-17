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
  bool _blocked = false; // Google refused the embedded webview

  static final _loginUrl = WebUri(
      'https://accounts.google.com/ServiceLogin?service=youtube&hl=en&continue=https://music.youtube.com/');

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
      body: _blocked
          ? _blockedHelp()
          : InAppWebView(
              initialUrlRequest: URLRequest(url: _loginUrl),
              initialSettings: InAppWebViewSettings(
                // Google blocks most embedded-webview logins ("browser not
                // secure"). A desktop Firefox UA is the most reliably accepted —
                // its check is more lenient than for Chrome/WebView UAs.
                userAgent:
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) '
                    'Gecko/20100101 Firefox/121.0',
                javaScriptEnabled: true,
                thirdPartyCookiesEnabled: true,
                // Present as a normal browser, not a headless/automated one.
                incognito: false,
              ),
              onLoadStop: (controller, url) async {
                if (url == null) return;
                // Google's "this browser or app may not be secure" wall — it
                // redirects to a *rejected* URL and/or sets that page title.
                if (url.host.contains('accounts.google.com')) {
                  final path = url.path.toLowerCase();
                  final title = (await controller.getTitle() ?? '').toLowerCase();
                  if (path.contains('rejected') ||
                      title.contains("couldn't sign you in") ||
                      title.contains('not secure')) {
                    if (mounted) setState(() => _blocked = true);
                    return;
                  }
                }
                // Once redirected back to music.youtube.com, cookies are set.
                if (url.host.contains('music.youtube.com')) {
                  await _tryCapture();
                }
              },
            ),
    );
  }

  Widget _blockedHelp() => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.gpp_maybe_outlined, color: PA.warning, size: 56),
            const SizedBox(height: 16),
            const Text('Google blocked in-app sign-in',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
                'Google sometimes refuses to sign in from an embedded browser. '
                'You can still browse and search YouTube Music without signing '
                'in — only your personalized recommendations need an account. '
                'Try again in a moment, or continue signed out.',
                textAlign: TextAlign.center,
                style: TextStyle(color: PA.textSecondary)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => setState(() => _blocked = false),
                  child: const Text('Try again'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: PA.accent, foregroundColor: Colors.black),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Continue signed out'),
                ),
              ],
            ),
          ],
        ),
      );
}
