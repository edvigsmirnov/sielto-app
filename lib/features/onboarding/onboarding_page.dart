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
import 'package:sielto/features/onboarding/onboarding_scaffold.dart';
import 'package:sielto/features/onboarding/welcome_page.dart';
import 'package:sielto/features/settings/language_picker.dart';
import 'package:sielto/features/spaces/space_form_page.dart';

/// First run (spec 2.1): one screen of basics, then the first Space.
///
/// No account, no email, no network call — the user id was generated locally
/// before this screen was built. App lock and the Recovery Key are steps 3 and
/// 4 of the spec's flow; they arrive with M7, and the progress bar counts the
/// steps that exist rather than pretending they are already there.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final PageController _controller = PageController();

  /// The basics, then the Space. The Space form is the last one.
  static const int _stepCount = 2;

  bool _started = false;

  final GlobalKey _welcome = GlobalKey();

  /// The welcome screen as it was when left, blowing away over the first
  /// step; null once it has.
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
          const SpaceFormPage(
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

/// Nickname, currency, theme and language on one screen.
///
/// Every answer here is changeable later in Settings, so none of them earns a
/// screen of its own. The currency is stored as the device default, so every
/// later Space starts from the same answer instead of asking again (spec 2.1,
/// step 2). Theme and language apply the moment they are picked.
class _ProfileStep extends ConsumerStatefulWidget {
  const _ProfileStep({required this.stepCount, required this.onContinue});

  final int stepCount;
  final VoidCallback onContinue;

  @override
  ConsumerState<_ProfileStep> createState() => _ProfileStepState();
}

class _ProfileStepState extends ConsumerState<_ProfileStep> {
  final TextEditingController _nickname = TextEditingController();
  String? _currency;

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _save(String currency) async {
    await ref.read(localSettingsProvider).setNickname(_nickname.text);
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
      children: <Widget>[
        LabelledField(
          label: tr('onboarding.fieldNickname'),
          child: TextField(
            controller: _nickname,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: tr('onboarding.nicknameHint'),
            ),
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
          // Drawn as a field, the same width and height as the currency one
          // above it; the picker is a sheet because the list grows.
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
