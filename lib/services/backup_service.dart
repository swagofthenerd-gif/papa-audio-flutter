import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Info about a single backup.
class BackupInfo {
  final String path;
  final DateTime date;
  final int sizeBytes;
  final String filename;

  const BackupInfo({
    required this.path,
    required this.date,
    required this.sizeBytes,
    required this.filename,
  });

  String get sizeFormatted {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Service for creating and restoring backups of app data.
///
/// Backs up SQLite databases, SharedPreferences, and settings files into a
/// zip archive. Supports listing, restoring, and deleting existing backups.
class BackupService {
  static const _backupDirName = 'papa_backups';
  static const _lastBackupPrefKey = 'last_auto_backup_date';

  /// Creates a backup zip of all app data and returns the file path.
  Future<String> createBackup() async {
    final appDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${appDir.path}/$_backupDirName');
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    // Collect all files to back up
    final filesToBackup = await _collectBackupFiles();

    if (filesToBackup.isEmpty) {
      throw Exception('No data files found to back up');
    }

    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final zipName = 'papa_audio_backup_$timestamp.zip';
    final zipPath = '${backupDir.path}/$zipName';
    final zipFile = File(zipPath);

    // Use a temporary directory to stage all files with their relative paths
    final stageDir =
        Directory('${appDir.path}/_backup_stage_${DateTime.now().millisecondsSinceEpoch}');
    await stageDir.create(recursive: true);

    try {
      // Copy all files to the stage directory, preserving relative structure
      for (final file in filesToBackup) {
        final relative =
            file.path.replaceFirst('${appDir.path}/', '');
        final destPath = '${stageDir.path}/$relative';
        final destFile = File(destPath);
        await destFile.parent.create(recursive: true);
        await file.copy(destPath);
      }

      // Zip the stage directory
      await ZipFile.createFromDirectory(
        sourceDir: stageDir,
        zipFile: zipFile,
        includeBaseDirectory: false,
        recurseSubDirs: true,
      );

      // Update last backup date in prefs
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastBackupPrefKey,
          DateTime.now().toIso8601String().substring(0, 10));

      return zipPath;
    } finally {
      // Clean up staging directory
      if (await stageDir.exists()) {
        await stageDir.delete(recursive: true);
      }
    }
  }

  /// Restores app data from a backup [zipPath].
  /// Files are extracted over the current app data.
  Future<void> restoreFromBackup(String zipPath) async {
    final zipFile = File(zipPath);
    if (!await zipFile.exists()) {
      throw Exception('Backup file not found: $zipPath');
    }

    final appDir = await getApplicationDocumentsDirectory();

    // Extract the zip to a temporary location first for safety
    final tempDir =
        Directory('${appDir.path}/_restore_temp_${DateTime.now().millisecondsSinceEpoch}');
    await tempDir.create(recursive: true);

    try {
      await ZipFile.extractToDirectory(
        zipFile: zipFile,
        destinationDir: tempDir,
      );

      // Copy extracted files over the real app data
      await _copyDirectory(tempDir, appDir);
    } finally {
      // Clean up temp directory
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  /// Lists all existing backups sorted by date (newest first).
  Future<List<BackupInfo>> listBackups() async {
    final appDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${appDir.path}/$_backupDirName');

    if (!await backupDir.exists()) {
      return [];
    }

    final backups = <BackupInfo>[];
    try {
      await for (final entity in backupDir.list()) {
        if (entity is File && entity.path.endsWith('.zip')) {
          final stat = await entity.stat();
          backups.add(BackupInfo(
            path: entity.path,
            date: stat.modified,
            sizeBytes: stat.size,
            filename: entity.path.split('/').last,
          ));
        }
      }
    } catch (_) {
      // Ignore listing errors
    }

    // Sort newest first
    backups.sort((a, b) => b.date.compareTo(a.date));
    return backups;
  }

  /// Deletes a specific backup file.
  Future<void> deleteBackup(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Deletes all backups.
  Future<void> deleteAllBackups() async {
    final backups = await listBackups();
    for (final b in backups) {
      await deleteBackup(b.path);
    }
  }

  /// Returns true if auto-backup should run today (once per day).
  Future<bool> shouldAutoBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final lastDate = prefs.getString(_lastBackupPrefKey);
    if (lastDate == null) return true;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return lastDate != today;
  }

  /// Performs auto-backup if one hasn't been done today.
  Future<String?> autoBackup() async {
    if (!await shouldAutoBackup()) return null;
    try {
      return await createBackup();
    } catch (_) {
      return null;
    }
  }

  /// Collects all files that should be included in a backup.
  Future<List<File>> _collectBackupFiles() async {
    final files = <File>[];
    final appDir = await getApplicationDocumentsDirectory();

    // SQLite database files
    try {
      final dbPath = await getDatabasesPath();
      final dbDir = Directory(dbPath);
      if (await dbDir.exists()) {
        await for (final entity in dbDir.list()) {
          if (entity is File) {
            // Include .db, .db-journal, .db-wal, .db-shm files
            final name = entity.path.split('/').last;
            if (name.startsWith('papa') ||
                name.contains('papa') ||
                name == 'databases.db') {
              files.add(entity);
              // Also grab associated journal/WAL/SHM files
              for (final suffix in ['-journal', '-wal', '-shm']) {
                final associated = File('${entity.path}$suffix');
                if (await associated.exists()) {
                  files.add(associated);
                }
              }
            }
          }
        }
      }
    } catch (_) {
      // Database path may not be available
    }

    // SharedPreferences XML files
    try {
      final prefsDir = Directory('${appDir.path}/shared_prefs');
      if (await prefsDir.exists()) {
        await for (final entity in prefsDir.list()) {
          if (entity is File) {
            files.add(entity);
          }
        }
      }
    } catch (_) {
      // May not exist
    }

    // Any additional app data directories / files
    try {
      // Include settings, playlists, queues, history data
      final dataSubDirs = [
        'playlists',
        'queues',
        'history',
        'downloads',
        'cache',
      ];
      for (final subDir in dataSubDirs) {
        final dir = Directory('${appDir.path}/$subDir');
        if (await dir.exists()) {
          await _addDirectoryContents(files, dir);
        }
      }
    } catch (_) {
      // Ignore
    }

    return files;
  }

  Future<void> _addDirectoryContents(
      List<File> files, Directory dir) async {
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          files.add(entity);
        }
      }
    } catch (_) {
      // Ignore permission errors
    }
  }

  /// Recursively copy from [source] to [destination].
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await for (final entity in source.list()) {
      final relativePath =
          entity.path.replaceFirst('${source.path}/', '');
      final destPath = '${destination.path}/$relativePath';

      if (entity is Directory) {
        final destDir = Directory(destPath);
        if (!await destDir.exists()) {
          await destDir.create(recursive: true);
        }
        await _copyDirectory(entity, destDir);
      } else if (entity is File) {
        final destFile = File(destPath);
        await destFile.parent.create(recursive: true);
        await entity.copy(destPath);
      }
    }
  }
}
