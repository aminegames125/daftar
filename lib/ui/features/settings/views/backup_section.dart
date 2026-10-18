import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../data/data_providers.dart';
import '../../../../data/services/backup/backup_service.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/widgets/floating_toast.dart';
import 'settings_widgets.dart';

/// Settings > Backup: save / share everything as one file, restore from one,
/// and export price history and transactions as CSV. Local only (no cloud).
class BackupSection extends ConsumerWidget {
  const BackupSection({super.key});

  BackupService _service(WidgetRef ref) =>
      BackupService(ref.read(appDatabaseProvider));

  String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}-${two(n.hour)}${two(n.minute)}';
  }

  Future<void> _share(
    BuildContext context,
    String fileName,
    String content,
    String subject,
  ) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(content, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: subject),
    );
  }

  Future<void> _export(
    BuildContext context,
    Future<String> Function() build,
    String fileName,
    String subject,
  ) async {
    try {
      final content = await build();
      if (!context.mounted) return;
      await _share(context, fileName, content, subject);
    } catch (_) {
      if (context.mounted) {
        FloatingToast.show(
          context,
          'Could not create the file',
          kind: ToastKind.error,
        );
      }
    }
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final service = _service(ref);
    final String text;
    final BackupSummary summary;
    try {
      final picked = await FilePicker.pickFile(
        dialogTitle: 'Choose a Daftar backup',
      );
      if (picked == null || picked.path == null) return;
      text = await File(picked.path!).readAsString();
      summary = service.inspect(text);
    } on BackupException catch (e) {
      if (context.mounted) {
        FloatingToast.show(context, e.message, kind: ToastKind.error);
      }
      return;
    } catch (_) {
      if (context.mounted) {
        FloatingToast.show(
          context,
          'Could not read that file',
          kind: ToastKind.error,
        );
      }
      return;
    }
    if (!context.mounted) return;

    final when =
        summary.exportedAt?.toLocal().toString().split('.').first ??
        'unknown date';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace all data?'),
        content: Text(
          'This backup was made on $when and holds ${summary.totalRows} records. '
          'Restoring replaces everything now on this phone. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      await service.restoreJson(text);
    } on BackupException catch (e) {
      if (context.mounted) {
        FloatingToast.show(context, e.message, kind: ToastKind.error);
      }
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backup restored'),
        content: const Text(
          'Close and reopen Daftar to see your restored data everywhere.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final service = _service(ref);
    final chevron = Icon(Icons.chevron_right_rounded, color: c.muted);
    return SettingsSection(
      title: 'Backup',
      children: [
        SettingsTile(
          icon: Icons.upload_file_outlined,
          title: 'Back up everything',
          subtitle: 'Save or share one file with all your data',
          trailing: chevron,
          onTap: () => _export(
            context,
            service.exportJson,
            'daftar-backup-${_stamp()}.json',
            'Daftar backup',
          ),
        ),
        SettingsTile(
          icon: Icons.settings_backup_restore_rounded,
          title: 'Restore from a backup',
          subtitle: 'Replaces the data on this phone',
          trailing: chevron,
          onTap: () => _restore(context, ref),
        ),
        SettingsTile(
          icon: Icons.table_chart_outlined,
          title: 'Export price history (CSV)',
          trailing: chevron,
          onTap: () => _export(
            context,
            service.priceHistoryCsv,
            'daftar-prices-${_stamp()}.csv',
            'Daftar price history',
          ),
        ),
        SettingsTile(
          icon: Icons.receipt_long_outlined,
          title: 'Export transactions (CSV)',
          trailing: chevron,
          onTap: () => _export(
            context,
            service.transactionsCsv,
            'daftar-transactions-${_stamp()}.csv',
            'Daftar transactions',
          ),
        ),
      ],
    );
  }
}
