import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/features/security/recovery_key.dart';
import 'package:sielto/features/sync/sync_controller.dart';

/// A fresh install joins an existing account with a code from another device.
class JoinPage extends ConsumerStatefulWidget {
  const JoinPage({super.key});

  @override
  ConsumerState<JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends ConsumerState<JoinPage> {
  final TextEditingController _code = TextEditingController();
  bool _busy = false;
  String? _problem;
  List<String>? _done;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    final ({JoinResult result, String? userId, String? recoveryKey}) joined =
        await ref.read(syncProvider.notifier).join(_code.text);
    if (!mounted) return;
    final String? userId = joined.userId;
    if (joined.result != JoinResult.joined || userId == null) {
      setState(() {
        _busy = false;
        _problem = switch (joined.result) {
          JoinResult.offlineMode => tr('storage.offlineMode'),
          JoinResult.noNetwork => tr('storage.noNetwork'),
          JoinResult.tooManyAttempts => tr('devices.tooManyAttempts'),
          _ => tr('devices.wrongCode'),
        };
      });
      return;
    }

    await ref.read(localSettingsProvider).adoptUserId(userId);
    await ref.read(localSettingsProvider).setJoinedAccount();
    ref.invalidate(userIdProvider);
    final String? recoveryKey = joined.recoveryKey;
    if (recoveryKey != null) {
      await ref.read(recoveryKeySetProvider.notifier).set(recoveryKey);
    }
    await ref.read(syncProvider.notifier).syncNow();
    if (!mounted) return;
    // The main screens are already underneath once a Space has arrived.
    final bool hasSpaces =
        (await ref.read(repositoriesProvider).spaces.watchAll().first)
            .isNotEmpty;
    if (!mounted) return;
    if (hasSpaces) {
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      if (recoveryKey == null) {
        messenger.showSnackBar(SnackBar(content: Text(tr('devices.keyLater'))));
      }
      return;
    }
    setState(() {
      _busy = false;
      _done = <String>[
        tr('devices.noSpaces'),
        if (recoveryKey == null) tr('devices.keyLater'),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<String>? done = _done;
    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: AppBar(title: Text(tr('devices.joinTitle'))),
      body: ListView(
        padding: const EdgeInsets.all(SageSpace.formGutter),
        children: <Widget>[
          if (done == null) ...<Widget>[
            Text(tr('devices.joinBody'), style: text.bodyMedium),
            const SizedBox(height: SageSpace.lg),
            LabelledField(
              label: tr('devices.codeField'),
              child: TextField(
                controller: _code,
                enabled: !_busy,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 8,
                textCapitalization: TextCapitalization.characters,
                onSubmitted: (String _) =>
                    _code.text.trim().length == 8 ? _join() : null,
              ),
            ),
            if (_problem case final String problem) ...<Widget>[
              const SizedBox(height: SageSpace.sm),
              Semantics(
                liveRegion: true,
                child: Text(problem, style: text.bodyMedium),
              ),
            ],
            const SizedBox(height: SageSpace.lg),
            FilledButton(
              onPressed: _busy || _code.text.trim().length != 8 ? null : _join,
              child: Text(tr(_busy ? 'devices.joining' : 'devices.join')),
            ),
          ] else ...<Widget>[
            for (final String line in done) ...<Widget>[
              Text(line, style: text.bodyLarge),
              const SizedBox(height: SageSpace.md),
            ],
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr('devices.continue')),
            ),
          ],
        ],
      ),
    );
  }
}
