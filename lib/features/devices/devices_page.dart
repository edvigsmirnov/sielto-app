import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/detail_host.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/core/ui/leaf_loader.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/devices/add_device_page.dart';
import 'package:sielto/features/security/security_page.dart';
import 'package:sielto/features/sync/sync_controller.dart';

enum _Action { rename, unlink }

/// The devices linked to this account: rename, unlink, add.
class DevicesPage extends ConsumerStatefulWidget {
  const DevicesPage({super.key});

  @override
  ConsumerState<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends ConsumerState<DevicesPage> {
  static const int _inactiveDays = 90;

  ({CloudResult result, List<LinkedDevice> devices})? _loaded;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loaded = null);
    final ({CloudResult result, List<LinkedDevice> devices}) loaded = await ref
        .read(syncProvider.notifier)
        .devices();
    if (mounted) setState(() => _loaded = loaded);
  }

  Future<void> _after(Future<bool> call) async {
    final bool done = await call;
    if (!mounted) return;
    if (!done) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('storage.noNetwork'))));
    }
    await _load();
  }

  Future<void> _act(LinkedDevice device, _Action action) async {
    final SyncController sync = ref.read(syncProvider.notifier);
    final String name = device.name ?? tr('devices.unnamed');
    switch (action) {
      case _Action.rename:
        final String? typed = await textDialog(
          context,
          title: tr('devices.renameTitle'),
          initial: device.name ?? '',
          maxLength: 60,
        );
        final String? trimmed = typed?.trim();
        if (trimmed == null || trimmed.isEmpty || trimmed == device.name) {
          return;
        }
        await _after(sync.renameDevice(device.id, trimmed));
      case _Action.unlink:
        final bool confirmed = await confirmDialog(
          context,
          title: tr(
            'devices.unlinkTitle',
            namedArgs: <String, String>{'name': name},
          ),
          body: tr('devices.unlinkBody'),
          confirmLabel: tr('devices.unlink'),
          isDestructive: true,
        );
        if (confirmed && mounted && await confirmIdentity(context, ref)) {
          await _after(sync.unlinkDevice(device.id));
        }
    }
  }

  Future<void> _unlinkOthers() async {
    final bool confirmed = await confirmDialog(
      context,
      title: tr('devices.unlinkOthersTitle'),
      body: tr('devices.unlinkOthersBody'),
      confirmLabel: tr('devices.unlink'),
      isDestructive: true,
    );
    if (confirmed && mounted && await confirmIdentity(context, ref)) {
      await _after(ref.read(syncProvider.notifier).unlinkOtherDevices());
    }
  }

  Future<void> _add() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => const AddDevicePage(),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ({CloudResult result, List<LinkedDevice> devices})? loaded = _loaded;
    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: sageAppBar(context, title: Text(tr('devices.listTitle'))),
      body: switch (loaded) {
        null => const Center(child: LeafLoader()),
        (result: CloudResult.done, devices: final List<LinkedDevice> devices) =>
          ListView(
            padding: const EdgeInsets.symmetric(vertical: SageSpace.md),
            children: <Widget>[
              for (final LinkedDevice device in devices) _tile(device, text),
              Padding(
                padding: const EdgeInsets.all(SageSpace.formGutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    FilledButton(
                      onPressed: _add,
                      child: Text(tr('devices.addTitle')),
                    ),
                    if (devices.length > 1) ...<Widget>[
                      const SizedBox(height: SageSpace.sm),
                      OutlinedButton(
                        onPressed: _unlinkOthers,
                        child: Text(tr('devices.unlinkOthers')),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        (result: final CloudResult result, devices: _) => EmptyState(
          message: tr(switch (result) {
            CloudResult.offlineMode => 'storage.offlineMode',
            CloudResult.unlinked => 'storage.unlinked',
            _ => 'storage.noNetwork',
          }),
          action: result == CloudResult.noNetwork
              ? FilledButton(
                  onPressed: _load,
                  child: Text(tr('devices.tryAgain')),
                )
              : null,
        ),
      },
    );
  }

  Widget _tile(LinkedDevice device, TextTheme text) {
    final int away = DateTime.now().difference(device.lastSeen).inDays;
    final String seen = device.current
        ? tr('devices.thisDevice')
        : away == 0
        ? tr('devices.activeToday')
        : tr(
            'devices.lastActive',
            args: <String>[
              DateLabels(context.locale.toString()).dayMonth(
                CalendarDate.fromDateTime(device.lastSeen.toLocal()),
                reference: CalendarDate.fromDateTime(DateTime.now()),
              ),
            ],
          );
    return ListTile(
      leading: const Icon(Icons.devices_outlined),
      title: Text(device.name ?? tr('devices.unnamed')),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(seen),
          if (!device.current && away >= _inactiveDays)
            Text(
              plural('devices.inactive', away),
              style: text.bodyMedium?.copyWith(color: context.sage.warning),
            ),
        ],
      ),
      trailing: PopupMenuButton<_Action>(
        tooltip: tr('devices.actions'),
        onSelected: (_Action action) => _act(device, action),
        itemBuilder: (BuildContext _) => <PopupMenuEntry<_Action>>[
          PopupMenuItem<_Action>(
            value: _Action.rename,
            child: Text(tr('devices.rename')),
          ),
          if (!device.current)
            PopupMenuItem<_Action>(
              value: _Action.unlink,
              child: Text(
                tr('devices.unlink'),
                style: TextStyle(color: context.sage.danger),
              ),
            ),
        ],
      ),
    );
  }
}
