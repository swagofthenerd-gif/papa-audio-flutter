import 'package:flutter/foundation.dart';

import 'models.dart';

/// Multi-select across every track list. Long-press starts a selection, taps
/// toggle while active, and the [SelectionBar] offers bulk actions. Ordered —
/// tracks act in the order they were selected.
class TrackSelection extends ChangeNotifier {
  final Map<String, Track> _sel = {};

  bool get active => _sel.isNotEmpty;
  int get count => _sel.length;
  List<Track> get tracks => _sel.values.toList();

  bool contains(Track t) => _sel.containsKey(t.key);

  void toggle(Track t) {
    if (_sel.remove(t.key) == null) _sel[t.key] = t;
    notifyListeners();
  }

  void addAll(Iterable<Track> tracks) {
    for (final t in tracks) {
      _sel[t.key] = t;
    }
    notifyListeners();
  }

  void clear() {
    if (_sel.isEmpty) return;
    _sel.clear();
    notifyListeners();
  }
}
