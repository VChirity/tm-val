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
          return AlertDialog(
            title: const Text('Atualizando da WTT'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(
                  value: progress.value > 0 ? progress.value : null,
                ),
                const SizedBox(height: 16),
                Text(progress.message),
              ],
            ),
          );
        },
      );
    },
  );

  try {
    final result = await syncService.syncFromWtt(
      onProgress: (message, value) {
        progressNotifier.value = _SyncProgress(message: message, value: value);
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
  const _SyncProgress({required this.message, required this.value});

  final String message;
  final double value;
}
