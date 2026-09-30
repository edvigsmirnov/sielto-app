import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/core/ui/form_fields.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/features/security/recovery_key.dart';

/// Linux without a keyring: the database password, set once and asked at
/// every start.
class PassphrasePage extends StatefulWidget {
  const PassphrasePage({
    required this.firstRun,
    required this.canRecover,
    required this.onSubmit,
    required this.onRecover,
    required this.onStartOver,
    super.key,
  });

  final bool firstRun;
  final bool canRecover;

  /// False for a wrong password.
  final Future<bool> Function(String passphrase) onSubmit;

  /// False for a wrong Recovery Key.
  final Future<bool> Function(String recoveryKey, String passphrase) onRecover;
  final Future<void> Function() onStartOver;

  @override
  State<PassphrasePage> createState() => _PassphrasePageState();
}

class _PassphrasePageState extends State<PassphrasePage> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _recoveryKey = TextEditingController();
  final NewRecoveryKey _next = NewRecoveryKey();
  bool _forgot = false;
  bool _busy = false;
  bool _wrong = false;

  @override
  void dispose() {
    _password.dispose();
    _recoveryKey.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _run(Future<bool> Function() action) async {
    setState(() {
      _busy = true;
      _wrong = false;
    });
    final bool ok = await action();
    if (mounted && !ok) {
      setState(() {
        _busy = false;
        _wrong = true;
      });
    }
  }

  Future<void> _startOver() async {
    if (await confirmDialog(
      context,
      title: tr('decryption.confirmTitle'),
      body: tr('decryption.confirmBody'),
      confirmLabel: tr('decryption.confirmAction'),
      isDestructive: true,
    )) {
      await widget.onStartOver();
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool newPassword = widget.firstRun || _forgot;
    return Scaffold(
      backgroundColor: context.sage.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListenableBuilder(
              listenable: _next.listenable,
              builder: (BuildContext context, Widget? _) => ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(SageSpace.xl),
                children: <Widget>[
                  Icon(
                    Icons.lock_outline,
                    size: 44,
                    color: context.sage.inkSecondary,
                  ),
                  const SizedBox(height: SageSpace.md),
                  Text(
                    tr(
                      widget.firstRun
                          ? 'passphrase.setTitle'
                          : _forgot
                          ? 'passphrase.forgotTitle'
                          : 'passphrase.enterTitle',
                    ),
                    style: text.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: SageSpace.sm),
                  Text(
                    tr(
                      _forgot && !widget.canRecover
                          ? 'passphrase.noRecovery'
                          : 'passphrase.why',
                    ),
                    style: text.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: SageSpace.lg),
                  if (_forgot && widget.canRecover) ...<Widget>[
                    LabelledField(
                      label: tr('recovery.title'),
                      child: SecretField(
                        controller: _recoveryKey,
                        autofocus: true,
                        errorText: _wrong ? tr('recovery.wrongKey') : null,
                      ),
                    ),
                    const SizedBox(height: SageSpace.lg),
                  ],
                  if (newPassword && (!_forgot || widget.canRecover))
                    NewRecoveryKeyFields(draft: _next)
                  else if (!_forgot)
                    SecretField(
                      controller: _password,
                      autofocus: true,
                      errorText: _wrong ? tr('passphrase.wrong') : null,
                      onSubmitted: (_) =>
                          _run(() => widget.onSubmit(_password.text)),
                    ),
                  const SizedBox(height: SageSpace.xl),
                  if (!_forgot || widget.canRecover)
                    FilledButton(
                      onPressed: _busy || (newPassword && !_next.valid)
                          ? null
                          : () => _run(
                              () => _forgot
                                  ? widget.onRecover(
                                      _recoveryKey.text,
                                      _next.first.text,
                                    )
                                  : widget.onSubmit(
                                      newPassword
                                          ? _next.first.text
                                          : _password.text,
                                    ),
                            ),
                      child: Text(
                        tr(_busy ? 'recovery.working' : 'common.continue'),
                      ),
                    ),
                  if (!widget.firstRun) ...<Widget>[
                    const SizedBox(height: SageSpace.sm),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _forgot = !_forgot;
                              _wrong = false;
                            }),
                      child: Text(
                        tr(_forgot ? 'common.cancel' : 'passphrase.forgot'),
                      ),
                    ),
                  ],
                  if (_forgot)
                    TextButton(
                      onPressed: _busy ? null : _startOver,
                      style: TextButton.styleFrom(
                        foregroundColor: context.sage.danger,
                      ),
                      child: Text(tr('decryption.startOver')),
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
