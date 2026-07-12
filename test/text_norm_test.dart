import 'package:flutter_test/flutter_test.dart';

import 'package:papa_audio/src/text_norm.dart';

void main() {
  group('normText', () {
    test('folds diacritics and case', () {
      expect(normText('Beyoncé'), 'beyonce');
      expect(normText('Björk'), 'bjork');
      expect(normText('Zażółć GĘŚLĄ jaźń'), 'zazolc gesla jazn');
      expect(normText('Mötley Crüe'), 'motley crue');
      expect(normText('  Weird   spacing  '), 'weird spacing');
    });

    test('leaves plain ascii alone', () {
      expect(normText('hello world 123'), 'hello world 123');
    });
  });

  group('blobMatches', () {
    test('requires all terms, any order', () {
      const blob = 'paranoid black sabbath 1970 metal';
      expect(blobMatches(blob, 'sabbath paranoid'), true);
      expect(blobMatches(blob, 'paranoid'), true);
      expect(blobMatches(blob, 'sabbath purple'), false);
      expect(blobMatches(blob, ''), true);
    });
  });

  group('TagSplitter', () {
    final splitter = TagSplitter(
      separators: [';', ' feat. ', ' ft. '],
      blacklist: {'AC/DC', 'Bone Thugs-N-Harmony'},
    );

    test('splits on separators and trims', () {
      expect(splitter.split('A; B feat. C'), ['A', 'B', 'C']);
      expect(splitter.split('Solo Artist'), ['Solo Artist']);
    });

    test('dedupes case-insensitively, keeps first casing', () {
      expect(splitter.split('Foo; foo; FOO'), ['Foo']);
    });

    test('never splits blacklisted names', () {
      final slashy = TagSplitter(separators: ['/'], blacklist: {'AC/DC'});
      expect(slashy.split('AC/DC'), ['AC/DC']);
      expect(slashy.split('Artist A/Artist B'), ['Artist A', 'Artist B']);
    });

    test('empty input yields nothing', () {
      expect(splitter.split('   '), isEmpty);
    });
  });
}
