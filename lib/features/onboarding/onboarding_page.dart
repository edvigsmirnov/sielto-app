import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/format/currencies.dart';
import 'package:sielto/core/l10n/app_locales.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/theme/theme_mode_controller.dart';
import 'package:sielto/core/ui/leaf_scatter.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/features/backup/backup_page.dart';
import 'package:sielto/features/onboarding/onboarding_scaffold.dart';
import 'package:sielto/features/onboarding/welcome_page.dart';
import 'package:sielto/features/security/app_lock.dart';
import 'package:sielto/features/security/recovery_key.dart';
import 'package:sielto/features/security/security_page.dart';
import 'package:sielto/features/settings/language_picker.dart';
import 'package:sielto/features/spaces/space_form_page.dart';

/// First run: basics, then the first Space.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final PageController _controller = PageController();

  // The PIN needs the keyring; the start password already guards the app.
  late final bool _protectStep = !ref.read(keyManagerProvider).usesPassphrase;
  late final int _stepCount = _protectStep ? 4 : 3;

  bool _started = false;

  final GlobalKey _welcome = GlobalKey();

  /// Snapshot of the welcome screen while it scatters.
  ui.Image? _leaving;
  Offset? _leavingFrom;

  @override
  void dispose() {
    _controller.dispose();
    _leaving?.dispose();
    super.dispose();
  }

  Future<void> _start(Offset from) async {
    final ui.Image? image = await snapshotOf(_welcome);
    if (!mounted) return;
    setState(() {
      _started = true;
      _leaving = image;
      _leavingFrom = from;
    });
  }

  void _left() {
    setState(() {
      _leaving?.dispose();
      _leaving = null;
    });
  }

  void _next() => _controller.nextPage(
    duration: const Duration(milliseconds: 240),
    curve: Curves.easeOutCubic,
  );

  @override
  Widget build(BuildContext context) {
    if (!_started) {
      return RepaintBoundary(
        key: _welcome,
        child: WelcomePage(onStart: _start),
      );
    }

    final ui.Image? leaving = _leaving;
    final Widget steps = Scaffold(
      backgroundColor: context.sage.surface,
      body: PageView(
        controller: _controller,
        physics: const NeverScrollableScrollPhysics(),
        children: <Widget>[
          _ProfileStep(stepCount: _stepCount, onContinue: _next),
          if (_protectStep)
            _ProtectStep(stepCount: _stepCount, onContinue: _next),
          _RecoveryKeyStep(
            step: _stepCount - 1,
            stepCount: _stepCount,
            onContinue: _next,
          ),
          SpaceFormPage(
            isFirstSpace: true,
            step: _stepCount,
            stepCount: _stepCount,
          ),
        ],
      ),
    );
    if (leaving == null) return steps;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        steps,
        LeafScatter(image: leaving, origin: _leavingFrom, onDone: _left),
      ],
    );
  }
}

/// Name, currency, theme and language. The currency becomes the default
/// for new Spaces; theme and language apply immediately.
class _ProfileStep extends ConsumerStatefulWidget {
  const _ProfileStep({required this.stepCount, required this.onContinue});

  final int stepCount;
  final VoidCallback onContinue;

  @override
  ConsumerState<_ProfileStep> createState() => _ProfileStepState();
}

class _ProfileStepState extends ConsumerState<_ProfileStep> {
  final TextEditingController _name = TextEditingController();
  String? _currency;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save(String currency) async {
    await ref.read(nameProvider.notifier).set(_name.text);
    await ref.read(localSettingsProvider).setCurrencyCode(currency);
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    final String locale = context.locale.toString();
    final String currency =
        _currency ??
        ref.read(localSettingsProvider).currencyCode ??
        Currencies.forLocale(locale);
    final ThemeMode themeMode = ref.watch(themeModeProvider);

    return OnboardingScaffold(
      step: 1,
      stepCount: widget.stepCount,
      title: tr('onboarding.profileTitle'),
      body: tr('onboarding.profileWhy'),
      primaryLabel: tr('common.next'),
      onPrimary: () => _save(currency),
      secondaryLabel: tr('backup.restoreInstead'),
      onSecondary: () => restoreBackup(context, ref),
      children: <Widget>[
        LabelledField(
          label: tr('onboarding.fieldName'),
          child: TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(hintText: tr('onboarding.nameHint')),
          ),
        ),
        const SizedBox(height: SageSpace.lg),
        LabelledField(
          label: tr('space.fieldCurrency'),
          child: DropdownButtonFormField<String>(
            initialValue: currency,
            items: <DropdownMenuItem<String>>[
              for (final String code in Currencies.offered(currency))
                DropdownMenuItem<String>(
                  value: code,
                  child: Text(Currencies.label(code, locale)),
                ),
            ],
            onChanged: (String? code) =>
                setState(() => _currency = code ?? currency),
          ),
        ),
        const SizedBox(height: SageSpace.xs),
        Text(
          tr('onboarding.currencyWhy'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: SageSpace.lg),
        LabelledField(
          label: tr('settings.theme'),
          child: SegmentedChoice<ThemeMode>(
            values: ThemeMode.values,
            selected: themeMode,
            labelOf: (ThemeMode mode) => tr('theme.${mode.name}'),
            onChanged: (ThemeMode mode) =>
                ref.read(themeModeProvider.notifier).set(mode),
          ),
        ),
        const SizedBox(height: SageSpace.lg),
        LabelledField(
          label: tr('settings.language'),
          // Same size as the currency field.
          child: InkWell(
            onTap: () => showLanguagePicker(context),
            borderRadius: BorderRadius.circular(SageRadius.button),
            child: InputDecorator(
              decoration: const InputDecoration(
                suffixIcon: Icon(Icons.arrow_drop_down),
              ),
              child: Text(
                AppLocales.resolve(context.locale).name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Optional; the Dashboard plate reminds while it is skipped.
class _RecoveryKeyStep extends ConsumerStatefulWidget {
  const _RecoveryKeyStep({
    required this.step,
    required this.stepCount,
    required this.onContinue,
  });

  final int step;
  final int stepCount;
  final VoidCallback onContinue;

  @override
  ConsumerState<_RecoveryKeyStep> createState() => _RecoveryKeyStepState();
}

class _RecoveryKeyStepState extends ConsumerState<_RecoveryKeyStep> {
  final NewRecoveryKey _draft = NewRecoveryKey();
  bool _busy = false;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    await ref.read(recoveryKeySetProvider.notifier).set(_draft.first.text);
    if (!mounted) return;
    setState(() => _busy = false);
    FocusScope.of(context).unfocus();
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _draft.listenable,
    builder: (BuildContext context, Widget? _) => OnboardingScaffold(
      step: widget.step,
      stepCount: widget.stepCount,
      title: tr('recovery.title'),
      body: tr('recovery.why'),
      primaryLabel: tr(_busy ? 'recovery.working' : 'recovery.saveAndContinue'),
      onPrimary: _busy || !_draft.valid ? null : _save,
      secondaryLabel: tr('recovery.later'),
      onSecondary: _busy ? null : widget.onContinue,
      children: <Widget>[NewRecoveryKeyFields(draft: _draft)],
    ),
  );
}

/// Optional app lock: a PIN, with biometrics where the device has them.
class _ProtectStep extends ConsumerWidget {
  const _ProtectStep({required this.stepCount, required this.onContinue});

  final int stepCount;
  final VoidCallback onContinue;

  Future<void> _setUp(BuildContext context, WidgetRef ref) async {
    final String? pin = await choosePin(context);
    if (pin == null) return;
    await ref.read(appLockEnabledProvider.notifier).enable(pin);
    if (await ref.read(biometricAvailableProvider.future)) {
      await ref.read(biometricUnlockProvider.notifier).set(value: true);
    }
    onContinue();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => OnboardingScaffold(
    step: 2,
    stepCount: stepCount,
    title: tr('security.protectTitle'),
    body: tr('security.protectWhy'),
    primaryLabel: tr('security.setPin'),
    onPrimary: () => _setUp(context, ref),
    secondaryLabel: tr('common.skip'),
    onSecondary: onContinue,
  );
}
