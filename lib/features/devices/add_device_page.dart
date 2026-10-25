import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/leaf_loader.dart';
import 'package:sielto/features/onboarding/onboarding_scaffold.dart';
import 'package:sielto/features/security/recovery_key.dart';
import 'package:sielto/features/sync/codes.dart';
import 'package:sielto/features/sync/sync_controller.dart';

enum _Stage { loading, waiting, linked, expired, failed, offline }

/// Shows a one-time code and hands the Recovery Key to the device that uses it.
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
    final String? recoveryKey = await ref
        .read(keyManagerProvider)
        .storedRecoveryKey();
    final bool linked = await sync.handOver(
      recoveryKey,
      keepGoing: () => mounted && DateTime.now().isBefore(_expires),
    );
    if (!mounted) return;
    setState(() => _stage = linked ? _Stage.linked : _Stage.expired);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SetupPage(
      title: tr('devices.addTitle'),
      card: false,
      children: <Widget>[
        Text(tr('devices.addBody'), style: text.bodyMedium),
        const SizedBox(height: SageSpace.xl),
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
            _Stage.linked => Text(tr('devices.linked'), style: text.bodyLarge),
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
