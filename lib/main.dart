import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/app/startup.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/l10n/app_locales.dart';
import 'package:sielto/core/l10n/pseudo_asset_loader.dart';
import 'package:sielto/core/settings/local_settings.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_theme.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/theme/theme_mode_controller.dart';
import 'package:sielto/features/launch/launch_curtain.dart';
import 'package:sielto/features/onboarding/onboarding_page.dart';
import 'package:sielto/features/security/decryption_failure_page.dart';
import 'package:sielto/features/shell/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  final LocalSettings settings = await LocalSettings.load();

  final Startup startup = await openDatabase();

  await LaunchCurtain.arm();

  // BudgetAppRoot.build returns the ProviderScope.
  // ignore: riverpod_lint/missing_provider_scope
  runApp(BudgetAppRoot(startup: startup, settings: settings));
}

/// [ProviderScope] must stay above [EasyLocalization]: dictionary loads
/// rebuild everything below it.
class BudgetAppRoot extends StatefulWidget {
  const BudgetAppRoot({
    required this.startup,
    required this.settings,
    super.key,
  });

  final Startup startup;
  final LocalSettings settings;

  @override
  State<BudgetAppRoot> createState() => _BudgetAppRootState();
}

class _BudgetAppRootState extends State<BudgetAppRoot> {
  late Startup _startup = widget.startup;

  Future<void> _startOver(StartupLocked locked) async {
    final Startup next = await startOver(locked.manager);
    if (mounted) setState(() => _startup = next);
  }

  @override
  Widget build(BuildContext context) {
    final Startup startup = _startup;
    return ProviderScope(
      overrides: [
        localSettingsProvider.overrideWithValue(widget.settings),
        if (startup is StartupReady)
          databaseProvider.overrideWithValue(startup.database),
      ],
      child: EasyLocalization(
        supportedLocales: AppLocales.supported,
        path: AppLocales.path,
        fallbackLocale: AppLocales.fallback,
        // Default true ignores CLDR plural rules.
        ignorePluralRules: false,
        assetLoader: const PseudoAssetLoader(),
        child: switch (startup) {
          StartupReady() => const AppGate(),
          final StartupLocked locked => BudgetApp(
            home: DecryptionFailurePage(onStartOver: () => _startOver(locked)),
          ),
        },
      ),
    );
  }
}

/// Chooses between onboarding and the main shell.
class AppGate extends ConsumerWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Space?> resolved = ref.watch(resolvedSpaceProvider);

    return switch (resolved) {
      AsyncData<Space?>(value: final Space? space) =>
        space == null
            ? const BudgetApp(home: OnboardingPage())
            : const BudgetApp(home: MainShell()),
      AsyncError<Space?>() => const BudgetApp(home: _StartupError()),
      _ => const BudgetApp(home: _StartupLoading()),
    };
  }
}

class _StartupLoading extends StatelessWidget {
  const _StartupLoading();

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: SageBrand.night);
}

class _StartupError extends StatelessWidget {
  const _StartupError();

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(tr('common.loadFailed'))));
}

class BudgetApp extends ConsumerWidget {
  const BudgetApp({required this.home, super.key});

  final Widget home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Sielto',
      debugShowCheckedModeBanner: false,
      theme: SageTheme.light,
      darkTheme: SageTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
      builder: (BuildContext context, Widget? child) {
        // System bars follow the theme where a screen sets none.
        final bool dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarIconBrightness: dark
                    ? Brightness.light
                    : Brightness.dark,
                systemNavigationBarContrastEnforced: false,
              ),
          child: LaunchCurtain(child: child ?? const SizedBox.shrink()),
        );
      },
      home: home,
    );
  }
}
