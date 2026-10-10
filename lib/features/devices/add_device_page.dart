import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/leaf_loader.dart';
import 'package:sielto/features/security/recovery_key.dart';
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
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
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
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (Timer _) {
      if (mounted) setState(() {});
    });

    final String? recoveryKey = await ref
        .read(keyManagerProvider)
        .storedRecoveryKey();
    final bool linked = await sync.handOver(
      recoveryKey,
      keepGoing: () => mounted && DateTime.now().isBefore(_expires),
    );
    _tick?.cancel();
    if (!mounted) return;
    setState(() => _stage = linked ? _Stage.linked : _Stage.expired);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Duration left = _expires.difference(DateTime.now());
    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: AppBar(title: Text(tr('devices.addTitle'))),
      body: ListView(
        padding: const EdgeInsets.all(SageSpace.formGutter),
        children: <Widget>[
          Text(tr('devices.addBody'), style: text.bodyMedium),
          const SizedBox(height: SageSpace.xl),
          switch (_stage) {
            _Stage.loading => const Center(child: LeafLoader()),
            _Stage.waiting => Column(
              children: <Widget>[
                SelectableText(
                  _code!,
                  textAlign: TextAlign.center,
                  style: text.displaySmall?.copyWith(
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: SageSpace.sm),
                Text(
                  tr('devices.expiresIn', args: <String>[_clock(left)]),
                  style: text.bodySmall,
                ),
                const SizedBox(height: SageSpace.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      label: Text(tr('devices.copy')),
                      onPressed: () => _copy(_code!),
                    ),
                    const SizedBox(width: SageSpace.sm),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.share_outlined, size: 18),
                      label: Text(tr('devices.share')),
                      onPressed: () =>
                          SharePlus.instance.share(ShareParams(text: _code)),
                    ),
                  ],
                ),
                const SizedBox(height: SageSpace.xl),
                Text(tr('devices.waiting'), style: text.bodyMedium),
              ],
            ),
            _Stage.linked => Text(tr('devices.linked'), style: text.bodyLarge),
            _Stage.offline => Text(
              tr('storage.offlineMode'),
              style: text.bodyLarge,
            ),
            _Stage.expired || _Stage.failed => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  tr(
                    _stage == _Stage.failed
                        ? 'storage.noNetwork'
                        : 'devices.expired',
                  ),
                  style: text.bodyLarge,
                ),
                const SizedBox(height: SageSpace.lg),
                FilledButton(
                  onPressed: _start,
                  child: Text(tr('devices.newCode')),
                ),
              ],
            ),
          },
        ],
      ),
    );
  }

  static String _clock(Duration left) =>
      '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}';

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr('devices.copied'))));
  }
}
