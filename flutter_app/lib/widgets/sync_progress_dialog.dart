import 'package:flutter/material.dart';

import '../services/wtt_sync_service.dart';

Future<WttSyncResult?> showWttSyncDialog(BuildContext context) async {
  final syncService = WttSyncService();
  final progressNotifier = ValueNotifier<_SyncProgress>(
    const _SyncProgress(message: 'Iniciando...', value: 0.05),
  );

  if (!context.mounted) {
    return null;
  }

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) {
      return ValueListenableBuilder<_SyncProgress>(
        valueListenable: progressNotifier,
        builder: (context, progress, child) {
          final percentLabel = '${(progress.value * 100).round()}%';
          final countMatch = RegExp(r'(\d+)/(\d+)').firstMatch(progress.message);

          return AlertDialog(
            title: const Text('Atualizando da WTT'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(
                  value: progress.value.clamp(0.0, 1.0),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      countMatch != null
                          ? '${countMatch.group(1)}/${countMatch.group(2)} atletas'
                          : 'Sincronizando...',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      percentLabel,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(progress.message),
                if (progress.subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    progress.subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          );
        },
      );
    },
  );

  try {
    final result = await syncService.syncFromWtt(
      onProgress: (message, value, {subtitle}) {
        progressNotifier.value = _SyncProgress(
          message: message,
          value: value,
          subtitle: subtitle,
        );
      },
    );

    progressNotifier.dispose();

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    return result;
  } catch (error) {
    progressNotifier.dispose();

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao atualizar: $error')),
      );
    }
    return null;
  }
}

class _SyncProgress {
  const _SyncProgress({
    required this.message,
    required this.value,
    this.subtitle,
  });

  final String message;
  final double value;
  final String? subtitle;
}
