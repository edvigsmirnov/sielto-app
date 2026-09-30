import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/features/security/pin_store.dart';

const int pinMinLength = 4;
const int pinMaxLength = 6;

/// Time in the background before the lock returns.
const Duration lockGrace = Duration(seconds: 45);

final Provider<PinStore> pinStoreProvider = Provider<PinStore>(
  (Ref ref) => const PinStore(),
);

class AppLockEnabledController extends Notifier<bool> {
  @override
  bool build() => ref.watch(localSettingsProvider).appLockEnabled;

  Future<void> enable(String pin) async {
    await ref.read(pinStoreProvider).set(pin);
    await ref.read(localSettingsProvider).setAppLockEnabled(value: true);
    state = true;
  }

  Future<void> disable() async {
    await ref.read(pinStoreProvider).clear();
    await ref.read(localSettingsProvider).setAppLockEnabled(value: false);
    await ref.read(biometricUnlockProvider.notifier).set(value: false);
    state = false;
  }
}

final NotifierProvider<AppLockEnabledController, bool> appLockEnabledProvider =
    NotifierProvider<AppLockEnabledController, bool>(
      AppLockEnabledController.new,
    );

class BiometricUnlockController extends Notifier<bool> {
  @override
  bool build() => ref.watch(localSettingsProvider).appLockBiometric;

  Future<void> set({required bool value}) async {
    await ref.read(localSettingsProvider).setAppLockBiometric(value: value);
    state = value;
  }
}

final NotifierProvider<BiometricUnlockController, bool>
biometricUnlockProvider = NotifierProvider<BiometricUnlockController, bool>(
  BiometricUnlockController.new,
);

/// local_auth has no Linux backend.
final FutureProvider<bool> biometricAvailableProvider = FutureProvider<bool>((
  Ref ref,
) async {
  if (Platform.isLinux) return false;
  try {
    return await LocalAuthentication().isDeviceSupported();
  } on Exception {
    return false;
  }
});

/// [retryCancelled] tries once more after a system cancel.
Future<bool> authenticateBiometric({bool retryCancelled = false}) async {
  try {
    return await LocalAuthentication().authenticate(
      localizedReason: tr('lock.biometricReason'),
      persistAcrossBackgrounding: true,
    );
  } on LocalAuthException catch (e) {
    if (retryCancelled &&
        (e.code == LocalAuthExceptionCode.systemCanceled ||
            e.code == LocalAuthExceptionCode.uiUnavailable)) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return authenticateBiometric();
    }
    return false;
  } on Exception {
    return false;
  }
}

/// True while the lock screen is up. Locked at a cold start, and again after
/// [lockGrace] in the background.
class AppLockController extends Notifier<bool> with WidgetsBindingObserver {
  DateTime? _hiddenAt;

  @override
  bool build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() => WidgetsBinding.instance.removeObserver(this));
    return ref.read(appLockEnabledProvider);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _hiddenAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        final DateTime? hiddenAt = _hiddenAt;
        _hiddenAt = null;
        if (hiddenAt != null &&
            DateTime.now().difference(hiddenAt) >= lockGrace &&
            ref.read(appLockEnabledProvider)) {
          this.state = true;
        }
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  void unlock() => state = false;
}

final NotifierProvider<AppLockController, bool> appLockProvider =
    NotifierProvider<AppLockController, bool>(AppLockController.new);

/// Covers [child] with the lock screen while locked.
class AppLockGate extends ConsumerWidget {
  const AppLockGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool locked = ref.watch(appLockProvider);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // Hidden from screen readers too, or they would read out the money.
        ExcludeSemantics(
          excluding: locked,
          child: ExcludeFocus(
            excluding: locked,
            child: IgnorePointer(ignoring: locked, child: child),
          ),
        ),
        // Appears at once, fades out.
        AnimatedSwitcher(
          duration: Duration.zero,
          reverseDuration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 250),
          child: locked ? const _LockScreen() : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _LockScreen extends ConsumerStatefulWidget {
  const _LockScreen();

  @override
  ConsumerState<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<_LockScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    // The keystore lost the PIN: no way to check it, so no lock.
    if (!await ref.read(pinStoreProvider).isSet()) {
      await ref.read(appLockEnabledProvider.notifier).disable();
      ref.read(appLockProvider.notifier).unlock();
      return;
    }
    if (!ref.read(biometricUnlockProvider)) return;
    await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
    if (mounted) await _biometric(retryCancelled: true);
  }

  Future<void> _biometric({bool retryCancelled = false}) async {
    if (await authenticateBiometric(retryCancelled: retryCancelled)) {
      ref.read(appLockProvider.notifier).unlock();
    }
  }

  @override
  Widget build(BuildContext context) => Material(
    color: context.sage.surface,
    child: SafeArea(
      child: PinEntry(
        title: tr('lock.enterPin'),
        check: (String pin) =>
            ref.read(pinStoreProvider).check(pin, DateTime.now()),
        onAccepted: (_) => ref.read(appLockProvider.notifier).unlock(),
        onBiometric: ref.watch(biometricUnlockProvider) ? _biometric : null,
      ),
    ),
  );
}

/// Dots and a keypad. [check] returns null to accept, else the time of the
/// next allowed attempt; without it any PIN of a valid length passes.
class PinEntry extends StatefulWidget {
  const PinEntry({
    required this.title,
    required this.onAccepted,
    this.check,
    this.onBiometric,
    this.error,
    super.key,
  });

  final String title;
  final Future<DateTime?> Function(String pin)? check;
  final ValueChanged<String> onAccepted;
  final VoidCallback? onBiometric;

  /// Shown until the next digit.
  final String? error;

  @override
  State<PinEntry> createState() => _PinEntryState();
}

class _PinEntryState extends State<PinEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  /// Dots of the rejected PIN, shown red while they shake.
  int _rejected = 0;

  String _pin = '';
  bool _busy = false;
  bool _wrong = false;
  DateTime? _retryAt;
  Timer? _tick;
  late String? _error = widget.error;

  @override
  void didUpdateWidget(PinEntry old) {
    super.didUpdateWidget(old);
    if (widget.error != old.error) _error = widget.error;
  }

  @override
  void dispose() {
    _tick?.cancel();
    _shake.dispose();
    super.dispose();
  }

  bool get _waiting => _retryAt != null && DateTime.now().isBefore(_retryAt!);

  void _type(String digit) {
    if (_busy || _waiting || _pin.length >= pinMaxLength) return;
    setState(() {
      _rejected = 0;
      _pin += digit;
      _wrong = false;
      _error = null;
    });
  }

  void _erase() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    if (_busy || _waiting || _pin.length < pinMinLength) return;
    final String pin = _pin;
    final Future<DateTime?> Function(String pin)? check = widget.check;
    if (check == null) {
      setState(() => _pin = '');
      widget.onAccepted(pin);
      return;
    }
    setState(() => _busy = true);
    final DateTime? retryAt = await check(pin);
    if (!mounted) return;
    if (retryAt == null) {
      widget.onAccepted(pin);
      return;
    }
    unawaited(HapticFeedback.heavyImpact());
    setState(() {
      _busy = false;
      _rejected = pin.length;
      _pin = '';
      _wrong = true;
      _retryAt = retryAt;
    });
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _rejected = 0);
    } else {
      unawaited(
        _shake.forward(from: 0).then((_) {
          if (mounted) setState(() => _rejected = 0);
        }),
      );
    }
    _tick?.cancel();
    if (_waiting) {
      _tick = Timer.periodic(const Duration(seconds: 1), (Timer t) {
        if (!_waiting) t.cancel();
        setState(() {});
      });
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final String? char = event.character;
    if (char != null && RegExp(r'^\d$').hasMatch(char)) {
      _type(char);
    } else if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _erase();
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      unawaited(_submit());
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  String? get _message {
    if (_waiting) {
      final int seconds = _retryAt!.difference(DateTime.now()).inSeconds + 1;
      return plural('lock.retryIn', seconds);
    }
    if (_wrong) return tr('lock.wrongPin');
    return _error;
  }

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) => Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(SageSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.lock_outline, size: 40, color: sage.inkSecondary),
                const SizedBox(height: SageSpace.md),
                Text(
                  widget.title,
                  style: text.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: SageSpace.xl),
                AnimatedBuilder(
                  animation: _shake,
                  builder: (BuildContext context, Widget? child) {
                    final double t = _shake.value;
                    return Transform.translate(
                      offset: Offset(
                        math.sin(t * math.pi * 6) * 12 * (1 - t),
                        0,
                      ),
                      child: child,
                    );
                  },
                  child: _Dots(
                    filled: _rejected > 0 ? _rejected : _pin.length,
                    rejected: _rejected > 0,
                  ),
                ),
                const SizedBox(height: SageSpace.md),
                SizedBox(
                  height: 20,
                  child: Text(
                    _message ?? '',
                    style: text.bodySmall?.copyWith(color: sage.danger),
                  ),
                ),
                const SizedBox(height: SageSpace.md),
                _Keypad(
                  keySize:
                      ((box.maxWidth - 2 * SageSpace.xl) / 3 - 2 * _Keypad.gap)
                          .clamp(48, 88),
                  onDigit: _type,
                  onErase: _erase,
                  onSubmit: _pin.length >= pinMinLength && !_waiting
                      ? _submit
                      : null,
                ),
                if (widget.onBiometric != null) ...<Widget>[
                  const SizedBox(height: SageSpace.md),
                  TextButton.icon(
                    onPressed: widget.onBiometric,
                    icon: const Icon(Icons.fingerprint),
                    label: Text(tr('lock.useBiometric')),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.filled, required this.rejected});

  final int filled;
  final bool rejected;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < pinMaxLength; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 16,
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < filled
                  ? (rejected ? sage.danger : sage.accent)
                  : Colors.transparent,
              border: Border.all(
                width: 1.5,
                color: i < filled
                    ? (rejected ? sage.danger : sage.accent)
                    : i < pinMinLength
                    ? sage.inkLabel
                    : sage.hairline,
              ),
            ),
          ),
      ],
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.keySize,
    required this.onDigit,
    required this.onErase,
    required this.onSubmit,
  });

  static const double gap = 8;

  final double keySize;
  final ValueChanged<String> onDigit;
  final VoidCallback onErase;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    // No tooltips: the lock screen sits above the Navigator's Overlay.
    Widget key(
      Widget label,
      VoidCallback? onTap, {
      String? tooltip,
      bool filled = false,
    }) => Semantics(
      label: tooltip,
      button: tooltip != null,
      onTap: tooltip == null ? null : onTap,
      excludeSemantics: tooltip != null,
      child: Padding(
        padding: const EdgeInsets.all(gap),
        child: SizedBox.square(
          dimension: keySize,
          child: IconButton(
            style: IconButton.styleFrom(
              backgroundColor: filled ? sage.card : Colors.transparent,
            ),
            onPressed: onTap == null
                ? null
                : () {
                    unawaited(HapticFeedback.lightImpact());
                    onTap();
                  },
            icon: label,
          ),
        ),
      ),
    );
    Widget digit(String d) => key(
      Text(d, style: Theme.of(context).textTheme.headlineMedium),
      () => onDigit(d),
      filled: true,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final List<String> row in const <List<String>>[
          <String>['1', '2', '3'],
          <String>['4', '5', '6'],
          <String>['7', '8', '9'],
        ])
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[for (final String d in row) digit(d)],
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            key(
              const Icon(Icons.backspace_outlined),
              onErase,
              tooltip: tr('lock.erase'),
            ),
            digit('0'),
            key(
              const Icon(Icons.check),
              onSubmit,
              tooltip: tr('common.continue'),
            ),
          ],
        ),
      ],
    );
  }
}
