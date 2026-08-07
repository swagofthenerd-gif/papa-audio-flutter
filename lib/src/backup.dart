import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'db.dart';

/// ZIP-based backup & restore of all app data.
/// Creates timestamped zip files containing DB, playlists, settings, etc.
class BackupController {
  BackupController._();
  static final BackupController inst = BackupController._();

  String? _defaultLocation;
  String? get defaultLocation => _defaultLocation;
  int _autoIntervalDays = 2;
  int get autoIntervalDays => _autoIntervalDays;
  AppDatabase? _db;

  void attachDatabase(AppDatabase db) => _db = db;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _defaultLocation = '${dir.path}/backups';
    await Directory(_defaultLocation!).create(recursive: true);
    _autoIntervalDays = 2;
    _checkAutoBackup();
  }

  set autoIntervalDays(int v) { _autoIntervalDays = v; }

  /// Create a full backup ZIP of all app data.
  Future<String> createBackup() async {
    final dir = Directory(_defaultLocation!);
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
    final name = 'papa_backup_$ts';
    final dest = '${dir.path}/$name';

    await Directory(dest).create(recursive: true);

    // Copy DB
    if (_db == null) return null;
    final dbPath = _db!.dbPath;
    if (await File(dbPath).exists()) {
      await File(dbPath).copy('$dest/db.sqlite');
    }

    // Copy settings JSON
    final prefsDir = '${(await getApplicationDocumentsDirectory()).path}';
    final settingsFile = File('$prefsDir/papa_settings.json');
    if (await settingsFile.exists()) {
      await settingsFile.copy('$dest/settings.json');
    }

    // Manifest
    final manifest = {
      'version': 1,
      'timestamp': DateTime.now().toIso8601String(),
      'app': 'Papa Audio',
    };
    await File('$dest/manifest.json').writeAsString(jsonEncode(manifest));

    // TODO: create actual ZIP archive; for now we use a flat directory
    return dest;
  }

  /// Restore from a backup directory.
  Future<bool> restoreFromPath(String srcPath) async {
    try {
      final srcDir = Directory(srcPath);
      if (!await srcDir.exists()) return false;

      // Restore DB
      final dbFile = File('${srcDir.path}/db.sqlite');
      if (await dbFile.exists()) {
        if (_db == null) return false;
    await dbFile.copy(_db!.dbPath);
      }

      // Restore settings
      final settingsFile = File('${srcDir.path}/settings.json');
      if (await settingsFile.exists()) {
        final prefsDir = '${(await getApplicationDocumentsDirectory()).path}';
        await settingsFile.copy('$prefsDir/papa_settings.json');
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Share latest backup via system share sheet.
  Future<void> shareLatest() async {
    final dir = Directory(_defaultLocation!);
    final entries = await dir.list().toList();
    entries.sort((a, b) => b.path.compareTo(a.path));
    if (entries.isNotEmpty) {
      // Share the manifest as a representative file
      await Share.shareXFiles([XFile('${entries.first.path}/manifest.json')],
          text: 'Papa Audio Backup');
    }
  }

  Future<void> _checkAutoBackup() async {
    if (_autoIntervalDays <= 0) return;
    final dir = Directory(_defaultLocation!);
    final entries = await dir.list().toList();
    if (entries.isEmpty) {
      await createBackup();
      return;
    }
    entries.sort((a, b) => b.path.compareTo(a.path));
    final lastPath = entries.first.path;
    final lastBackup = await File('$lastPath/manifest.json').readAsString().then(
        (s) => jsonDecode(s)['timestamp'] as String).catchError((_) => '');
    if (lastBackup.isNotEmpty) {
      final lastDate = DateTime.parse(lastBackup);
      if (DateTime.now().difference(lastDate).inDays >= _autoIntervalDays) {
        await createBackup();
        // Trim old backups (keep max 10)
        final all = await dir.list().toList();
        all.sort((a, b) => b.path.compareTo(a.path));
        for (int i = 10; i < all.length; i++) {
          await all[i].delete(recursive: true);
        }
      }
    }
  }
}
