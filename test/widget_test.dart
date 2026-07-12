import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:papa_audio/main.dart';
import 'package:papa_audio/src/app_state.dart';
import 'package:papa_audio/src/models.dart';
import 'package:papa_audio/src/ui/widgets.dart';

void main() {
  testWidgets('shows setup screen when no bridge is configured', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: AppState(), child: const PapaApp()),
    );
    expect(find.text('Papa Audio'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
  });

  group('YtResult.fromJson tolerates server field variants', () {
    test('videoId + author + m:ss duration', () {
      final v = YtResult.fromJson({
        'videoId': 'abc123xyz00',
        'title': 'Song',
        'author': 'Channel',
        'duration': '3:35',
      });
      expect(v.id, 'abc123xyz00');
      expect(v.channel, 'Channel');
      expect(v.durationSec, 215);
    });

    test('id extracted from a watch URL, thumbnail from list', () {
      final v = YtResult.fromJson({
        'url': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'title': 'Song',
        'thumbnails': [
          {'url': 'https://i.ytimg.com/vi/x/default.jpg'}
        ],
        'lengthSeconds': 212,
      });
      expect(v.id, 'dQw4w9WgXcQ');
      expect(v.thumbnail, 'https://i.ytimg.com/vi/x/default.jpg');
      expect(v.durationSec, 212);
    });
  });

  test('fmtDuration formats minutes and hours', () {
    expect(fmtDuration(215), '3:35');
    expect(fmtDuration(3755), '1:02:35');
    expect(fmtDuration(0), '0:00');
  });
}
