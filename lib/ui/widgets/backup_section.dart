import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/backup_service.dart';
import '../../src/theme.dart';

/// A widget that displays backup creation, listing, restore, and delete
/// controls. Designed to be embedded in the Settings screen.
class BackupSection extends StatefulWidget {
  const BackupSection({super.key});

  @override
  State<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<BackupSection> {
  final _service = BackupService();
  List<BackupInfo> _backups = [];
  bool _loading = true;
  bool _creating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    try {
      final backups = await _service.listBackups();
      if (!mounted) return;
      setState(() {
        _backups = backups;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _createBackup() async {
    setState(() => _creating = true);
    try {
      final path = await _service.createBackup();
      if (!mounted) return;
      final name = path.split('/').last;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup created: $name',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          behavior: SnackBarBehavior.floating,
          backgroundColor: PA.accent,
        ),
      );
      await _loadBackups();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup failed: $e',
              maxLines: 2, overflow: TextOverflow.ellipsis),
          behavior: SnackBarBehavior.floating,
          backgroundColor: PA.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _restoreBackup(BackupInfo info) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PA.surfaceElevated,
        title: const Text('Restore Backup'),
        content: Text(
            'This will replace all current app data with the backup from '
            '${_fmtDate(info.date)}.\n\n'
            'The app may need to be restarted afterwards.\n\n'
            'Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore',
                style: TextStyle(color: PA.warning)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _service.restoreFromBackup(info.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Backup restored! Please restart the app for changes to take effect.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: PA.accent,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Restore failed: $e',
              maxLines: 2, overflow: TextOverflow.ellipsis),
          behavior: SnackBarBehavior.floating,
          backgroundColor: PA.error,
        ),
      );
    }
  }

  Future<void> _deleteBackup(BackupInfo info) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PA.surfaceElevated,
        title: const Text('Delete Backup'),
        content: Text('Delete backup from ${_fmtDate(info.date)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Delete', style: TextStyle(color: PA.error)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _service.deleteBackup(info.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Backup deleted'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadBackups();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delete failed: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: PA.error,
        ),
      );
    }
  }

  Future<void> _importBackup() async {
    // Scan backup directory for zip files the user placed there manually
    try {
      final backups = await _service.listBackups();
      if (!mounted) return;
      if (backups.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No backup files found. Place .zip files in the Papa Audio backups folder.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      // Show dialog to pick from existing backups
      final selected = await showDialog<BackupInfo>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Select Backup to Restore'),
          children: backups.map((b) => SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, b),
            child: Text('${b.filename}\n${b.sizeFormatted} • ${b.date}'),
          )).toList(),
        ),
      );
      if (selected != null) {
        _restoreBackup(selected);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: PA.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: PA.card,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.backup_outlined, color: PA.accent, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Backup & Restore',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                // Create backup button
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: PA.accent,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                  onPressed: _creating ? null : _createBackup,
                  icon: _creating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.add, size: 16, color: Colors.black),
                  label: Text(_creating ? 'Creating…' : 'Backup',
                      style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
                'Save and restore your playlists, settings, and library data.',
                style: TextStyle(color: PA.textMuted, fontSize: 11)),
            const SizedBox(height: 10),

            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: PA.accent),
                ),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_error!,
                    style: const TextStyle(color: PA.error, fontSize: 12)),
              )
            else ...[
              // Backup list
              if (_backups.isNotEmpty)
                ..._backups.map((b) => _BackupTile(
                      backup: b,
                      onRestore: () => _restoreBackup(b),
                      onDelete: () => _deleteBackup(b),
                    )),
              if (_backups.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('No backups yet.',
                      style:
                          TextStyle(color: PA.textMuted, fontSize: 12)),
                ),
              const SizedBox(height: 6),
              // Import button
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: PA.textSecondary,
                  side: const BorderSide(color: PA.separator),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                ),
                onPressed: _importBackup,
                icon: const Icon(Icons.file_open, size: 16),
                label: const Text('Import backup file',
                    style: TextStyle(fontSize: 12)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

class _BackupTile extends StatelessWidget {
  final BackupInfo backup;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _BackupTile({
    required this.backup,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const Icon(Icons.archive_outlined, color: PA.textMuted, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${backup.date.year}-${backup.date.month.toString().padLeft(2, '0')}-${backup.date.day.toString().padLeft(2, '0')} ${backup.date.hour.toString().padLeft(2, '0')}:${backup.date.minute.toString().padLeft(2, '0')}',
                    style:
                        const TextStyle(fontSize: 12, color: PA.text)),
                Text(backup.sizeFormatted,
                    style: const TextStyle(
                        color: PA.textMuted, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Restore',
            icon: const Icon(Icons.restore, size: 18, color: PA.warning),
            onPressed: onRestore,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline,
                size: 18, color: PA.error),
            onPressed: onDelete,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
