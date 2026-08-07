import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../settings.dart';
import '../local_library.dart';
import '../theme.dart';

/// First-run onboarding screen — configure critical settings before entering the app.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  bool _mediaPermission = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _completed = prefs.getBool('onboarding_complete') ?? false);
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    if (mounted) Navigator.of(context).pushReplacementNamed('/');
  }

  @override
  Widget build(BuildContext context) {
    if (_completed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.of(context).pushReplacementNamed('/'));
      return const SizedBox.shrink();
    }
    return Scaffold(
      backgroundColor: PapaColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              Icon(Icons.music_note_rounded, size: 80, color: PapaColors.accent),
              const SizedBox(height: 16),
              Text('Welcome to Papa Audio', style: PapaText.largeTitle),
              const SizedBox(height: 8),
              const Text('Let\'s set up your music experience.',
                textAlign: TextAlign.center,
                style: TextStyle(color: PapaColors.textSecondary, fontSize: 14)),
              const Spacer(),
              // Media permission
              _card(
                icon: Icons.folder_open,
                title: 'Access Your Music',
                subtitle: 'Grant permission to scan your local music files.',
                trailing: ElevatedButton(
                  onPressed: _mediaPermission ? null : () async {
                    final ok = await LocalLibrary.requestPermission();
                    setState(() => _mediaPermission = ok);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: _mediaPermission ? Colors.green : PapaColors.accent),
                  child: Text(_mediaPermission ? '✓ Granted' : 'Grant', style: const TextStyle(color: Colors.white)),
                ),
              ),
              const SizedBox(height: 12),
              _card(
                icon: Icons.computer,
                title: 'Connect to PC',
                subtitle: 'Optionally connect to your PC bridge server for streaming.',
                trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: PapaColors.textMuted),
              ),
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: _finish,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PapaColors.accent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Get Started', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.black)),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card({required IconData icon, required String title, required String subtitle, required Widget trailing}) {
    return Card(
      color: PapaColors.card,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Icon(icon, color: PapaColors.accent, size: 28),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(color: PapaColors.textSecondary, fontSize: 12)),
            ],
          )),
          trailing,
        ]),
      ),
    );
  }
}
