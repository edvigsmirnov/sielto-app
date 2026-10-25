import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/sync/device_link.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/core/ui/leaf_loader.dart';
import 'package:sielto/features/onboarding/onboarding_scaffold.dart';
import 'package:sielto/features/security/security_page.dart';
import 'package:sielto/features/sync/codes.dart';
import 'package:sielto/features/sync/sync_controller.dart';

enum _Stage {
  loading,
  waiting,
  asking,
  linked,
  refused,
  expired,
  failed,
  offline,
}

/// Shows a one-time code; the device that uses it joins once allowed here.
class AddDevicePage extends ConsumerStatefulWidget {
  const AddDevicePage({super.key});

  @override
  ConsumerState<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends ConsumerState<AddDevicePage> {
  static const Duration _life = Duration(minutes: 5);

  _Stage _stage = _Stage.loading;
  String? _code;
  DateTime _expires = DateTime.now();
  LinkClaim? _claim;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    setState(() => _stage = _Stage.loading);
    if (ref.read(offlineModeProvider)) {
      setState(() => _stage = _Stage.offline);
      return;
    }
    final SyncController sync = ref.read(syncProvider.notifier);
    final String? code = await sync.newLinkCode();
    if (!mounted) return;
    if (code == null) {
      setState(() => _stage = _Stage.failed);
      return;
    }
    setState(() {
      _code = code;
      _expires = DateTime.now().add(_life);
      _stage = _Stage.waiting;
    });
    final LinkClaim? claim = await sync.waitForClaim(
      keepGoing: () => mounted && DateTime.now().isBefore(_expires),
    );
    if (!mounted) return;
    setState(() {
      _claim = claim;
      _stage = claim == null ? _Stage.expired : _Stage.asking;
    });
  }

  Future<void> _answer({required bool allow}) async {
    final LinkClaim? claim = _claim;
    if (claim == null) return;
    if (allow && !await confirmIdentity(context, ref)) return;
    final bool answered = await ref
        .read(syncProvider.notifier)
        .answerClaim(claim, allow: allow);
    if (!mounted) return;
    setState(
      () => _stage = !answered
          ? _Stage.expired
          : allow
          ? _Stage.linked
          : _Stage.refused,
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SetupPage(
      title: tr('devices.addTitle'),
      card: false,
      children: <Widget>[
        if (_stage == _Stage.loading || _stage == _Stage.waiting) ...<Widget>[
          Text(tr('devices.addBody'), style: text.bodyMedium),
          const SizedBox(height: SageSpace.xl),
        ],
        Semantics(
          liveRegion: _stage != _Stage.loading && _stage != _Stage.waiting,
          child: switch (_stage) {
            _Stage.loading => const Center(child: LeafLoader()),
            _Stage.waiting => Column(
              children: <Widget>[
                CodeCard(code: _code!, expires: _expires),
                const SizedBox(height: SageSpace.xl),
                Text(tr('devices.waiting'), style: text.bodyMedium),
              ],
            ),
            _Stage.asking => _Ask(
              name: _claim?.name ?? tr('devices.unnamed'),
              onAnswer: _answer,
            ),
            _Stage.linked => Text(tr('devices.linked'), style: text.bodyLarge),
            _Stage.refused => CodeRetry(
              message: tr('devices.refusedThere'),
              onRetry: _start,
            ),
            _Stage.offline => Text(
              tr('storage.offlineMode'),
              style: text.bodyLarge,
            ),
            _Stage.expired || _Stage.failed => CodeRetry(
              message: tr(
                _stage == _Stage.failed
                    ? 'storage.noNetwork'
                    : 'devices.expired',
              ),
              onRetry: _start,
            ),
          },
        ),
      ],
    );
  }
}

/// Which device claimed the code, and the owner's answer.
class _Ask extends StatelessWidget {
  const _Ask({required this.name, required this.onAnswer});

  final String name;
  final Future<void> Function({required bool allow}) onAnswer;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          tr('devices.askTitle', namedArgs: <String, String>{'name': name}),
          style: text.titleMedium,
        ),
        const SizedBox(height: SageSpace.sm),
        Text(tr('devices.askBody'), style: text.bodyMedium),
        const SizedBox(height: SageSpace.lg),
        ChoiceGrid(
          choices: <(String, VoidCallback)>[
            (tr('devices.refuse'), () => onAnswer(allow: false)),
            (tr('devices.allow'), () => onAnswer(allow: true)),
          ],
          primaryLast: true,
        ),
      ],
    );
  }
}
