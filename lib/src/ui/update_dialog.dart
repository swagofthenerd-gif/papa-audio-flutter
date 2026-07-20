import 'package:flutter/material.dart';

import '../theme.dart';
import '../update_service.dart';

/// Centered "Update available" dialog. Shows the new version + changelog and
/// downloads/installs in place (progress bar), then hands off to the Android
/// installer. Non-dismissible while downloading.
Future<void> showUpdateDialog(BuildContext context, UpdateService updates) {
  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) => _UpdateDialog(updates: updates),
  );
}

class _UpdateDialog extends StatefulWidget {
  final UpdateService updates;
  const _UpdateDialog({required this.updates});
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _update() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.updates.downloadAndInstall();
      // The Android installer takes over here; leave the dialog up in case the
      // user cancels the system prompt.
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.updates.available;
    if (info == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: widget.updates,
      builder: (context, _) {
        final progress = widget.updates.downloadProgress;
        return AlertDialog(
          backgroundColor: PA.surfaceElevated,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PA.rLg)),
          title: Row(
            children: [
              const Icon(Icons.system_update, color: PA.accent),
              const SizedBox(width: 10),
              Expanded(child: Text('Update available',
                  style: const TextStyle(fontSize: 18))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Version ${info.versionName} is ready to install.',
                  style: const TextStyle(color: PA.textSecondary, fontSize: 13)),
              if (info.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: SingleChildScrollView(
                    child: Text(info.notes,
                        style: const TextStyle(
                            color: PA.textMuted, fontSize: 12, height: 1.4)),
                  ),
                ),
              ],
              if (progress != null) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    color: PA.accent,
                    backgroundColor: PA.card,
                  ),
                ),
                const SizedBox(height: 6),
                Text('Downloading… ${(progress * 100).round()}%',
                    style: const TextStyle(color: PA.textMuted, fontSize: 11)),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(color: PA.error, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            if (!_busy)
              TextButton(
                onPressed: () {
                  widget.updates.dismiss();
                  Navigator.pop(context);
                },
                child: const Text('Later',
                    style: TextStyle(color: PA.textSecondary)),
              ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: PA.accent, foregroundColor: Colors.black),
              onPressed: _busy ? null : _update,
              child: Text(_error != null ? 'Retry' : 'Update now'),
            ),
          ],
        );
      },
    );
  }
}
