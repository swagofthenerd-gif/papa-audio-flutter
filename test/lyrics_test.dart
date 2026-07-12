import 'package:flutter_test/flutter_test.dart';

import 'package:papa_audio/src/lyrics.dart';

void main() {
  group('parseLrc', () {
    test('parses timestamps, sorts, skips metadata tags', () {
      const raw = '[ar:Test Artist]\n'
          '[00:12.50] second line\n'
          '[00:01] first line\n'
          'no stamp here\n'
          '[01:02.5] third line\n';
      final lines = parseLrc(raw);
      expect(lines.length, 3);
      expect(lines[0].text, 'first line');
      expect(lines[0].at, const Duration(seconds: 1));
      expect(lines[1].at, const Duration(seconds: 12, milliseconds: 500));
      expect(lines[2].at, const Duration(minutes: 1, seconds: 2, milliseconds: 500));
    });

    test('repeated timestamps share one text', () {
      final lines = parseLrc('[00:05][00:30] chorus line');
      expect(lines.length, 2);
      expect(lines[0].text, 'chorus line');
      expect(lines[1].at, const Duration(seconds: 30));
    });
  });

  group('lrcLineIndexAt', () {
    final lines = parseLrc('[00:10] a\n[00:20] b\n[00:30] c');
    test('before first line', () {
      expect(lrcLineIndexAt(lines, const Duration(seconds: 5)), -1);
    });
    test('exact and between stamps', () {
      expect(lrcLineIndexAt(lines, const Duration(seconds: 10)), 0);
      expect(lrcLineIndexAt(lines, const Duration(seconds: 25)), 1);
      expect(lrcLineIndexAt(lines, const Duration(minutes: 5)), 2);
    });
  });
}
