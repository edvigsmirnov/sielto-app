import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/core/ui/layout.dart';
import 'package:sielto/features/onboarding/onboarding_scaffold.dart';
import 'package:sielto/features/security/recovery_key.dart';
import 'package:sielto/features/sync/codes.dart';
import 'package:sielto/features/sync/sync_controller.dart';

/// A fresh install joins an existing account with a code from another device.
class JoinPage extends ConsumerStatefulWidget {
  const JoinPage({super.key});

  @override
  ConsumerState<JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends ConsumerState<JoinPage> {
  bool _busy = false;
  String? _problem;
  List<String>? _done;

  Future<void> _join(String code) async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    final ({JoinResult result, String? userId, String? recoveryKey}) joined =
        await ref.read(syncProvider.notifier).join(code);
    if (!mounted) return;
    final String? userId = joined.userId;
    if (joined.result != JoinResult.joined || userId == null) {
      setState(() {
        _busy = false;
        _problem = codeProblem(joined.result, wrongCode: 'devices.wrongCode');
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
        messenger.say(tr('devices.keyLater'));
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
    final List<String>? done = _done;
    final bool wide = isWide(context);
    return SetupPage(
      title: tr('devices.joinTitle'),
      card: wide,
      children: <Widget>[
        if (done == null)
          CodeEntry(
            body: tr('devices.joinBody'),
            bodyAlign: wide ? TextAlign.center : TextAlign.start,
            action: tr('devices.join'),
            busyAction: tr('devices.joining'),
            busy: _busy,
            problem: _problem,
            onSubmit: _join,
          )
        else ...<Widget>[
          for (final String line in done) ...<Widget>[
            Text(line, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: SageSpace.md),
          ],
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('devices.continue')),
          ),
        ],
      ],
    );
  }
}
