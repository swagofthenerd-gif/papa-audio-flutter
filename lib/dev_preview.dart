// Dev-only harness: `flutter run -t lib/dev_preview.dart -d chrome|emulator`.
// Boots the real Shell without needing a reachable PC bridge and queues two
// public test tracks so the player (mini bar, morph, full player, queue) can
// be exercised end to end. Never shipped — the release entrypoint is main.dart.
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';

import 'main.dart';
import 'src/app_state.dart';
import 'src/models.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Same audio stack as production — this harness must exercise the real
  // background-playback + pipeline path on Android.
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.shaharyar.papaudio.audio',
      androidNotificationChannelName: 'Papa Audio',
      androidNotificationOngoing: true,
    );
  } catch (_) {}
  final state = AppState();
  // Pretend a bridge is configured so Root shows the Shell (calls that hit
  // the bridge will just fail fast — that's fine for UI work).
  state.bridge.baseUrl = 'http://127.0.0.1:9';
  runApp(ChangeNotifierProvider.value(value: state, child: const PapaApp()));

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await Future.delayed(const Duration(milliseconds: 800));
    await state.playerService.playQueue(const [
      Track(
        id: 'demo1',
        title: 'Demo Track One',
        artist: 'SoundHelix',
        album: 'Test Album',
        filePath: '',
        duration: 372,
        sourceUri: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
      ),
      Track(
        id: 'demo2',
        title: 'Demo Track Two (longer title to check ellipsis behavior)',
        artist: 'SoundHelix',
        album: 'Test Album',
        filePath: '',
        duration: 425,
        sourceUri: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
      ),
      Track(
        id: 'demo3',
        title: 'Demo Track Three',
        artist: 'SoundHelix',
        album: 'Test Album',
        filePath: '',
        duration: 289,
        sourceUri: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
      ),
    ], 0);
  });
}
