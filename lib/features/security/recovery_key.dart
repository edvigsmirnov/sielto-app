import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/crypto/envelope.dart';
import 'package:sielto/core/crypto/key_store.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/detail_host.dart';
import 'package:sielto/core/ui/form_fields.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/features/backup/drive.dart';

/// Overridden at startup alongside the database.
final Provider<DatabaseKeyManager> keyManagerProvider =
    Provider<DatabaseKeyManager>(
      (Ref ref) => throw StateError('keyManagerProvider was not overridden'),
    );

class RecoveryKeyController extends Notifier<bool> {
  @override
  bool build() => ref.watch(keyManagerProvider).hasRecoveryKey;

  Future<void> set(String recoveryKey) async {
    await ref.read(keyManagerProvider).setRecoveryKey(recoveryKey);
    state = true;
  }

  /// Throws [EnvelopeException] when [current] is wrong.
  Future<void> change(String current, String next) =>
      ref.read(keyManagerProvider).changeRecoveryKey(current, next);
}

/// Whether envelope B exists on this device.
final NotifierProvider<RecoveryKeyController, bool> recoveryKeySetProvider =
    NotifierProvider<RecoveryKeyController, bool>(RecoveryKeyController.new);

const int recoveryKeyMinLength = 8;

/// A new Recovery Key typed twice.
class NewRecoveryKey {
  final TextEditingController first = TextEditingController();
  final TextEditingController repeat = TextEditingController();

  Listenable get listenable => Listenable.merge(<Listenable>[first, repeat]);

  bool get valid =>
      first.text.length >= recoveryKeyMinLength && first.text == repeat.text;

  void dispose() {
    first.dispose();
    repeat.dispose();
  }
}

class NewRecoveryKeyFields extends StatelessWidget {
  const NewRecoveryKeyFields({required this.draft, this.onDone, super.key});

  final NewRecoveryKey draft;

  /// Enter in the second field, once both match.
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: draft.listenable,
    builder: (BuildContext context, Widget? _) {
      final String first = draft.first.text;
      final String repeat = draft.repeat.text;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LabelledField(
            label: tr('recovery.fieldKey'),
            child: SecretField(
              controller: draft.first,
              errorText: first.isNotEmpty && first.length < recoveryKeyMinLength
                  ? plural('recovery.tooShort', recoveryKeyMinLength)
                  : null,
            ),
          ),
          const SizedBox(height: SageSpace.lg),
          LabelledField(
            label: tr('recovery.fieldRepeat'),
            child: SecretField(
              controller: draft.repeat,
              errorText: repeat.isNotEmpty && repeat != first
                  ? tr('recovery.mismatch')
                  : null,
              onSubmitted: (_) {
                if (draft.valid) onDone?.call();
              },
            ),
          ),
        ],
      );
    },
  );
}

/// Sets the Recovery Key, or changes it when one is set.
class RecoveryKeyPage extends ConsumerStatefulWidget {
  const RecoveryKeyPage({super.key});

  @override
  ConsumerState<RecoveryKeyPage> createState() => _RecoveryKeyPageState();
}

class _RecoveryKeyPageState extends ConsumerState<RecoveryKeyPage> {
  final TextEditingController _current = TextEditingController();
  final NewRecoveryKey _next = NewRecoveryKey();
  late final bool _changing = ref.read(recoveryKeySetProvider);

  /// The key exists on another device: typed once, nothing to confirm.
  late final bool _existing =
      !_changing && ref.read(localSettingsProvider).joinedAccount;
  bool _busy = false;
  bool _wrongCurrent = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _wrongCurrent = false;
    });
    final RecoveryKeyController controller = ref.read(
      recoveryKeySetProvider.notifier,
    );
    try {
      if (_changing) {
        await controller.change(_current.text, _next.first.text);
      } else {
        await controller.set(_next.first.text);
      }
    } on EnvelopeException {
      if (mounted) {
        setState(() {
          _busy = false;
          _wrongCurrent = true;
        });
      }
      return;
    }
    // A fresh snapshot under the new key.
    if (_changing && driveSupported) {
      unawaited(ref.read(driveProvider.notifier).backUp(interactive: false));
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr(_changing ? 'recovery.changed' : 'recovery.saved')),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: sageAppBar(
        context,
        title: Text(tr(_changing ? 'recovery.changeTitle' : 'recovery.title')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(SageSpace.formGutter),
        children: <Widget>[
          Text(
            tr(_existing ? 'recovery.existingWhy' : 'recovery.why'),
            style: text.bodySmall,
          ),
          const SizedBox(height: SageSpace.lg),
          if (_changing) ...<Widget>[
            LabelledField(
              label: tr('recovery.fieldCurrent'),
              child: SecretField(
                controller: _current,
                autofocus: true,
                errorText: _wrongCurrent ? tr('recovery.wrongKey') : null,
              ),
            ),
            const SizedBox(height: SageSpace.lg),
          ],
          if (_existing)
            LabelledField(
              label: tr('recovery.title'),
              child: SecretField(controller: _next.first, autofocus: true),
            )
          else
            NewRecoveryKeyFields(draft: _next, onDone: _busy ? null : _save),
          if (_changing) ...<Widget>[
            const SizedBox(height: SageSpace.md),
            Text(tr('recovery.oldBackups'), style: text.bodySmall),
          ],
        ],
      ),
      bottomNavigationBar: FormActionBar(
        child: ListenableBuilder(
          listenable: _next.listenable,
          builder: (BuildContext context, Widget? _) => FilledButton(
            onPressed:
                _busy ||
                    !(_existing
                        ? _next.first.text.length >= recoveryKeyMinLength
                        : _next.valid)
                ? null
                : _save,
            child: Text(tr(_busy ? 'recovery.working' : 'common.save')),
          ),
        ),
      ),
    );
  }
}

/// Asks for the Recovery Key. [onSubmit] returns false for a wrong key.
Future<void> showRecoveryKeyPrompt(
  BuildContext context, {
  required Future<bool> Function(String recoveryKey) onSubmit,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (BuildContext context) => _RecoveryKeyPrompt(onSubmit: onSubmit),
);

class _RecoveryKeyPrompt extends StatefulWidget {
  const _RecoveryKeyPrompt({required this.onSubmit});

  final Future<bool> Function(String recoveryKey) onSubmit;

  @override
  State<_RecoveryKeyPrompt> createState() => _RecoveryKeyPromptState();
}

class _RecoveryKeyPromptState extends State<_RecoveryKeyPrompt> {
  final TextEditingController _key = TextEditingController();
  bool _busy = false;
  bool _wrong = false;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _key.text.isEmpty) return;
    setState(() {
      _busy = true;
      _wrong = false;
    });
    final bool opened = await widget.onSubmit(_key.text);
    if (!mounted) return;
    if (opened) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _wrong = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr('decryption.enterRecoveryKey')),
    content: SecretField(
      controller: _key,
      autofocus: true,
      errorText: _wrong ? tr('recovery.wrongKey') : null,
      onSubmitted: (_) => _submit(),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        child: Text(tr('common.cancel')),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: Text(tr(_busy ? 'recovery.working' : 'common.continue')),
      ),
    ],
  );
}

/// On the Dashboard while no Recovery Key is set.
class RecoveryKeyPlate extends ConsumerWidget {
  const RecoveryKeyPlate({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(recoveryKeySetProvider) ||
        ref.watch(backupPlateClosedProvider)) {
      return const SizedBox.shrink();
    }
    final SageColors sage = context.sage;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SageSpace.gutter,
        0,
        SageSpace.gutter,
        SageSpace.sm,
      ),
      child: Material(
        color: sage.warningTint,
        borderRadius: BorderRadius.circular(SageRadius.card),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Semantics(
                container: true,
                button: true,
                child: InkWell(
                  onTap: onTap,
                  child: Container(
                    constraints: const BoxConstraints(
                      minHeight: kMinInteractiveDimension,
                    ),
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      SageSpace.md,
                      SageSpace.sm,
                      SageSpace.xs,
                      SageSpace.sm,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.shield_outlined,
                          size: 18,
                          color: sage.warning,
                        ),
                        const SizedBox(width: SageSpace.sm),
                        Expanded(
                          child: Text(
                            tr(
                              ref.watch(localSettingsProvider).joinedAccount
                                  ? 'recovery.plateExisting'
                                  : 'recovery.plate',
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: sage.inkLabel,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: tr('common.close'),
              icon: Icon(Icons.close, size: 18, color: sage.inkLabel),
              onPressed: ref.read(backupPlateClosedProvider.notifier).close,
            ),
          ],
        ),
      ),
    );
  }
}
