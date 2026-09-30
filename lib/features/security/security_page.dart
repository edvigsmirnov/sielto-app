import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/features/security/app_lock.dart';
import 'package:sielto/features/security/recovery_key.dart';

/// `FLAG_SECURE` on Android. Desktop platforms have nothing equivalent.
abstract final class ScreenshotGuard {
  static const MethodChannel _channel = MethodChannel('sielto/window');

  static bool get supported => Platform.isAndroid;

  static Future<void> apply({required bool block}) async {
    if (supported) await _channel.invokeMethod<void>('setSecure', block);
  }
}

class BlockScreenshotsController extends Notifier<bool> {
  @override
  bool build() => ref.watch(localSettingsProvider).blockScreenshots;

  Future<void> set({required bool value}) async {
    await ref.read(localSettingsProvider).setBlockScreenshots(value: value);
    await ScreenshotGuard.apply(block: value);
    state = value;
  }
}

final NotifierProvider<BlockScreenshotsController, bool>
blockScreenshotsProvider = NotifierProvider<BlockScreenshotsController, bool>(
  BlockScreenshotsController.new,
);

/// A new PIN typed twice. Null when abandoned.
Future<String?> choosePin(BuildContext context) => Navigator.of(context)
    .push<String>(
      MaterialPageRoute<String>(
        builder: (BuildContext _) => const _ChoosePin(),
      ),
    );

/// True once the current PIN is entered.
Future<bool> confirmPin(BuildContext context, WidgetRef ref) async =>
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => Scaffold(
          backgroundColor: context.sage.surface,
          appBar: AppBar(),
          body: PinEntry(
            title: tr('lock.enterCurrentPin'),
            check: (String pin) =>
                ref.read(pinStoreProvider).check(pin, DateTime.now()),
            onAccepted: (_) => Navigator.of(context).pop(true),
          ),
        ),
      ),
    ) ??
    false;

class _ChoosePin extends StatefulWidget {
  const _ChoosePin();

  @override
  State<_ChoosePin> createState() => _ChoosePinState();
}

class _ChoosePinState extends State<_ChoosePin> {
  String? _first;
  String? _error;

  void _accept(String pin) {
    final String? first = _first;
    if (first == null) {
      setState(() {
        _first = pin;
        _error = null;
      });
    } else if (first == pin) {
      Navigator.of(context).pop(pin);
    } else {
      setState(() {
        _first = null;
        _error = tr('lock.pinsDiffer');
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.sage.surface,
    appBar: AppBar(),
    body: PinEntry(
      key: ValueKey<bool>(_first == null),
      title: tr(_first == null ? 'lock.choosePin' : 'lock.repeatPin'),
      error: _error,
      onAccepted: _accept,
    ),
  );
}

/// App lock and screenshot protection.
class SecurityPage extends ConsumerWidget {
  const SecurityPage({super.key});

  Future<void> _toggleLock(
    BuildContext context,
    WidgetRef ref, {
    required bool on,
  }) async {
    if (on) {
      final String? pin = await choosePin(context);
      if (pin == null) return;
      await ref.read(appLockEnabledProvider.notifier).enable(pin);
      final bool biometric = await ref.read(biometricAvailableProvider.future);
      if (biometric) {
        await ref.read(biometricUnlockProvider.notifier).set(value: true);
      }
    } else if (await confirmPin(context, ref)) {
      await ref.read(appLockEnabledProvider.notifier).disable();
    }
  }

  Future<void> _changePin(BuildContext context, WidgetRef ref) async {
    if (!await confirmPin(context, ref) || !context.mounted) return;
    final String? pin = await choosePin(context);
    if (pin == null) return;
    await ref.read(pinStoreProvider).set(pin);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('lock.pinChanged'))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool enabled = ref.watch(appLockEnabledProvider);
    // The PIN needs the keyring; the start password already guards the app.
    final bool passphrase = ref.watch(keyManagerProvider).usesPassphrase;
    final bool biometricAvailable =
        ref.watch(biometricAvailableProvider).value ?? false;
    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: AppBar(title: Text(tr('security.title'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: SageSpace.md),
        children: <Widget>[
          SwitchListTile.adaptive(
            secondary: const Icon(Icons.lock_outline),
            title: Text(tr('security.appLock')),
            subtitle: Text(
              tr(
                passphrase
                    ? 'security.passwordAtStart'
                    : 'security.appLockHint',
              ),
            ),
            value: enabled,
            onChanged: passphrase
                ? null
                : (bool on) => _toggleLock(context, ref, on: on),
          ),
          if (enabled && biometricAvailable)
            SwitchListTile.adaptive(
              secondary: const Icon(Icons.fingerprint),
              title: Text(tr('security.biometric')),
              value: ref.watch(biometricUnlockProvider),
              onChanged: (bool value) =>
                  ref.read(biometricUnlockProvider.notifier).set(value: value),
            ),
          if (enabled)
            ListTile(
              leading: const Icon(Icons.pin_outlined),
              title: Text(tr('security.changePin')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _changePin(context, ref),
            ),
          SectionLabel(tr('security.privacy')),
          if (ScreenshotGuard.supported)
            SwitchListTile.adaptive(
              secondary: const Icon(Icons.screenshot_outlined),
              title: Text(tr('security.blockScreenshots')),
              subtitle: Text(tr('security.blockScreenshotsHint')),
              value: ref.watch(blockScreenshotsProvider),
              onChanged: (bool value) =>
                  ref.read(blockScreenshotsProvider.notifier).set(value: value),
            )
          else
            ListTile(
              enabled: false,
              leading: const Icon(Icons.screenshot_outlined),
              title: Text(tr('security.blockScreenshots')),
              subtitle: Text(tr('security.noScreenshotBlockOnDesktop')),
            ),
        ],
      ),
    );
  }
}
