import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';

/// About Papa Audio page — version info, credits, changelog, license.
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});
  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> with TickerProviderStateMixin {
  String _version = '';
  bool _spinIcon = false;
  late final AnimationController _spinCtrl;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() => _version = '${info.version}+${info.buildNumber}');
  }

  void _spinEasterEgg() {
    if (_spinIcon) return;
    setState(() => _spinIcon = true);
    _spinCtrl.repeat();
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(seconds: 2), () {
      _spinCtrl.stop();
      setState(() => _spinIcon = false);
    });
  }

  @override
  void dispose() { _spinCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('About Papa Audio')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // App icon + name
          Center(
            child: Column(children: [
              GestureDetector(
                onDoubleTap: _spinEasterEgg,
                child: RotationTransition(
                  turns: _spinCtrl,
                  child: Container(
                    width: 96, height: 96,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: PapaColors.accent.withOpacity(0.15),
                    ),
                    child: const Icon(Icons.music_note_rounded, size: 48, color: PapaColors.accent),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('Papa Audio', style: PapaText.largeTitle),
              const SizedBox(height: 4),
              Text(_version, style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
              const SizedBox(height: 8),
              Text('A premium music player with PC bridge streaming & Soulseek.',
                textAlign: TextAlign.center,
                style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 13)),
            ]),
          ),
          const SizedBox(height: 32),
          // Development
          _sectionHeader('Development'),
          _tile(Icons.code, 'GitHub', 'swagofthenerd-gif/papa-audio-flutter',
              () => launchUrl(Uri.parse('https://github.com/swagofthenerd-gif/papa-audio-flutter'))),
          _tile(Icons.bug_report, 'Report an Issue', 'Found a bug? Let us know.',
              () => launchUrl(Uri.parse('https://github.com/swagofthenerd-gif/papa-audio-flutter/issues'))),
          _tile(Icons.description, 'Changelog', 'See what\'s new',
              () => launchUrl(Uri.parse('https://github.com/swagofthenerd-gif/papa-audio-flutter/blob/main/CHANGELOG.md'))),
          const SizedBox(height: 24),
          _sectionHeader('Other'),
          _tile(Icons.article, 'License', 'MIT License', () {
            showLicensePage(context: context, applicationName: 'Papa Audio', applicationVersion: _version,
              applicationLegalese: '© ${DateTime.now().year} Papa Audio');
          }),
          _tile(Icons.share, 'Share app', 'Tell your friends about Papa Audio', () {
            Share.share('Check out Papa Audio — the best music player with PC streaming!');
          }),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Text(text, style: TextStyle(color: PapaColors.accent, fontWeight: FontWeight.w600, fontSize: 12)),
  );

  Widget _tile(IconData icon, String title, String subtitle, VoidCallback onTap) => Card(
    margin: const EdgeInsets.symmetric(vertical: 4),
    child: ListTile(leading: Icon(icon, color: PapaColors.accent), title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)), onTap: onTap),
  );
}
