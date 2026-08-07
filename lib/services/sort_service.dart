import 'dart:math';

import '../src/models.dart';

/// Advanced sort types for any track list.
enum SortType {
  title,
  artist,
  album,
  duration,
  dateAdded,
  playCount,
  year,
  random,
}

/// Pure static sort helpers. No state, no dependencies — works on any
/// `List<Track>` in the app (library, playlist, queue, search results…).
class SortService {
  SortService._();

  /// Returns a new sorted copy. [playCounts] is optional — when provided
  /// (keyed by track.key), [SortType.playCount] uses it; otherwise playCount
  /// falls back to title sort with a warning ignored at runtime.
  static List<Track> sort(
    List<Track> tracks,
    SortType type, {
    bool ascending = true,
    Map<String, int>? playCounts,
  }) {
    final list = List<Track>.of(tracks);
    switch (type) {
      case SortType.title:
        list.sort((a, b) => _cmp(a.title, b.title) * (ascending ? 1 : -1));
      case SortType.artist:
        list.sort((a, b) => _cmp(a.artist, b.artist) * (ascending ? 1 : -1));
      case SortType.album:
        list.sort((a, b) =>
            _cmp(a.album ?? '', b.album ?? '') * (ascending ? 1 : -1));
      case SortType.duration:
        list.sort((a, b) =>
            a.duration.compareTo(b.duration) * (ascending ? 1 : -1));
      case SortType.dateAdded:
        list.sort((a, b) =>
            a.dateAdded.compareTo(b.dateAdded) * (ascending ? 1 : -1));
      case SortType.year:
        list.sort((a, b) => a.year.compareTo(b.year) * (ascending ? 1 : -1));
      case SortType.playCount:
        final counts = playCounts ?? {};
        list.sort((a, b) {
          final ca = counts[a.key] ?? 0;
          final cb = counts[b.key] ?? 0;
          return ca.compareTo(cb) * (ascending ? 1 : -1);
        });
      case SortType.random:
        list.shuffle(Random());
    }
    return list;
  }

  static int _cmp(String a, String b) =>
      a.toLowerCase().trim().compareTo(b.toLowerCase().trim());

  /// Human-readable label for each sort type.
  static String labelOf(SortType t) => switch (t) {
        SortType.title => 'Title',
        SortType.artist => 'Artist',
        SortType.album => 'Album',
        SortType.duration => 'Duration',
        SortType.dateAdded => 'Added',
        SortType.playCount => 'Plays',
        SortType.year => 'Year',
        SortType.random => 'Random',
      };

  /// Icon for each sort type (used in chips and menus).
  static String iconOf(SortType t) => switch (t) {
        SortType.title => 'abc',
        SortType.artist => 'person',
        SortType.album => 'album',
        SortType.duration => 'timer',
        SortType.dateAdded => 'calendar_today',
        SortType.playCount => 'bar_chart',
        SortType.year => 'calendar_month',
        SortType.random => 'shuffle',
      };
}
