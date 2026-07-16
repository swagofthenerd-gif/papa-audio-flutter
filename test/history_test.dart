import 'package:flutter_test/flutter_test.dart';
import 'package:papa_audio/src/history.dart';
import 'package:papa_audio/src/models.dart';

// Verifies the Wave 1 listen-counting fixes without a database (in-memory only;
// _db stays null so _record just updates the aggregate maps).
void main() {
  Track track(String id) =>
      Track(id: id, title: 't', artist: 'a', filePath: '/$id', duration: 0);

  test('repeated plays of the same track each count (repeat-one / restart)', () {
    final h = HistoryService();
    h.thresholdProvider = (_) => 2.0; // counts after 2 accrued seconds
    final t = track('x');

    // First play: two ticks with rising position → one listen.
    h.onPositionTick(t, positionSec: 1);
    h.onPositionTick(t, positionSec: 2);
    expect(h.counts['x'], 1);

    // Keep playing past the threshold — still just one listen.
    h.onPositionTick(t, positionSec: 3);
    expect(h.counts['x'], 1);

    // Track loops back to the start (position resets) → a new listen accrues.
    h.onPositionTick(t, positionSec: 0);
    h.onPositionTick(t, positionSec: 1);
    expect(h.counts['x'], 2);
  });

  test('removeEntry clears aggregates when the last listen is deleted', () {
    final h = HistoryService();
    h.thresholdProvider = (_) => 1.0;
    final t = track('y');
    h.onPositionTick(t, positionSec: 1);
    expect(h.counts['y'], 1);
    expect(h.lastListen.containsKey('y'), isTrue);

    h.removeEntry(h.entries.first);
    expect(h.counts.containsKey('y'), isFalse);
    expect(h.lastListen.containsKey('y'), isFalse);
    expect(h.firstListen.containsKey('y'), isFalse);
  });
}
