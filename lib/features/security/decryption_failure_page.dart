import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';

/// Shown when the database exists but its key does not. Only "Start over"
/// works for now.
class DecryptionFailurePage extends StatelessWidget {
  const DecryptionFailurePage({required this.onStartOver, super.key});

  final Future<void> Function() onStartOver;

  Future<void> _confirm(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('decryption.confirmTitle'.tr()),
        content: Text('decryption.confirmBody'.tr()),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('decryption.confirmAction'.tr()),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await onStartOver();
  }

  @override
  Widget build(BuildContext context) {
    final SageColors c = context.sage;
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(SageSpace.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                spacing: SageSpace.md,
                children: <Widget>[
                  Icon(Icons.lock_outline, size: 44, color: c.inkSecondary),
                  const SizedBox(height: SageSpace.xs),
                  Text(
                    'decryption.title'.tr(),
                    style: text.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'decryption.body'.tr(),
                    style: text.bodyMedium?.copyWith(color: c.inkSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: SageSpace.md),

                  // Shown disabled until recovery is implemented.
                  _Unavailable(label: 'decryption.enterRecoveryKey'.tr()),
                  _Unavailable(label: 'decryption.restoreFromBackup'.tr()),

                  const SizedBox(height: SageSpace.sm),
                  OutlinedButton(
                    onPressed: () => _confirm(context),
                    style: OutlinedButton.styleFrom(foregroundColor: c.danger),
                    child: Text('decryption.startOver'.tr()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final SageColors c = context.sage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FilledButton(onPressed: null, child: Text(label)),
        Padding(
          padding: const EdgeInsets.only(top: SageSpace.xs),
          child: Text(
            'decryption.notYetAvailable'.tr(),
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: c.inkLabel),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
