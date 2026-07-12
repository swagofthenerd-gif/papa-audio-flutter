import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Auto-archive of played queues: every new queue is snapshotted with its
/// timestamp so any listening session can be replayed later from the Queues
/// tab. Capped — old snapshots roll off.
class QueuesStore extends ChangeNotifier {
  static const _cap = 30;

  List<SavedQueue> saved = []; // newest first
  File? _file;

  Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    _file = File('${docs.path}${Platform.pathSeparator}queues.json');
    try {
      if (await _file!.exists()) {
        final list = await compute(_decodeList, await _file!.readAsString());
        saved = list
            .map((e) => SavedQueue.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      saved = [];
    }
    notifyListeners();
  }

  /// Called by the player whenever a NEW queue starts. Replaying the same set
  /// of tracks refreshes the existing snapshot instead of duplicating it.
  void record(List<Track> tracks) {
    if (tracks.isEmpty) return;
    final sig = tracks.map((t) => t.key).join('');
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = saved.indexWhere((q) => q.sig == sig);
    if (existing >= 0) {
      final q = saved.removeAt(existing);
      saved.insert(0, SavedQueue(at: now, tracks: q.tracks));
    } else {
      saved.insert(0, SavedQueue(at: now, tracks: List.of(tracks)));
      if (saved.length > _cap) saved.removeRange(_cap, saved.length);
    }
    notifyListeners();
    _save();
  }

  Future<void> delete(SavedQueue q) async {
    saved.remove(q);
    notifyListeners();
    await _save();
  }

  bool _saving = false;
  Future<void> _save() async {
    final f = _file;
    if (f == null || _saving) return;
    _saving = true;
    await Future.delayed(const Duration(seconds: 1));
    _saving = false;
    try {
      await f.writeAsString(
          jsonEncode(saved.map((q) => q.toJson()).toList()));
    } catch (_) {}
  }
}

List<dynamic> _decodeList(String raw) => jsonDecode(raw) as List;

class SavedQueue {
  final int at; // epoch ms
  final List<Track> tracks;
  late final String sig = tracks.map((t) => t.key).join('');

  SavedQueue({required this.at, required this.tracks});

  factory SavedQueue.fromJson(Map<String, dynamic> j) => SavedQueue(
        at: (j['at'] as num?)?.toInt() ?? 0,
        tracks: ((j['tracks'] ?? []) as List)
            .map((t) => Track.fromJson(t as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() =>
      {'at': at, 'tracks': tracks.map((t) => t.toJson()).toList()};
}
