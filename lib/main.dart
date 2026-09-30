import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/app/startup.dart';
import 'package:sielto/core/backup/backup_service.dart';
import 'package:sielto/core/crypto/envelope.dart';
import 'package:sielto/core/crypto/key_store.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/l10n/app_locales.dart';
import 'package:sielto/core/l10n/pseudo_asset_loader.dart';
import 'package:sielto/core/settings/local_settings.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_theme.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/theme/theme_mode_controller.dart';
import 'package:sielto/core/time/space_clock.dart';
import 'package:sielto/features/launch/launch_curtain.dart';
import 'package:sielto/features/onboarding/onboarding_page.dart';
import 'package:sielto/features/security/app_lock.dart';
import 'package:sielto/features/security/decryption_failure_page.dart';
import 'package:sielto/features/security/passphrase_page.dart';
import 'package:sielto/features/security/recovery_key.dart';
import 'package:sielto/features/security/security_page.dart';
import 'package:sielto/features/shell/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  final LocalSettings settings = await LocalSettings.load();

  final Startup startup = await openDatabase();
  await ScreenshotGuard.apply(block: settings.blockScreenshots);

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

  Future<void> _restore(
    StartupLocked locked,
    BackupContents backup,
    String recoveryKey,
  ) async {
    final StartupReady next = await startOver(locked.manager) as StartupReady;
    await BackupService(
      db: next.database,
      clock: SpaceClock(timezone: 'UTC'),
      userId: widget.settings.userId,
    ).restore(backup, const <String, RestoreChoice>{});
    await next.manager.setRecoveryKey(recoveryKey);
    if (mounted) setState(() => _startup = next);
  }

  Future<bool> _openWithPassphrase(
    StartupNeedsPassphrase needs,
    String passphrase,
  ) async {
    final Startup next = await openDatabase(
      directory: needs.directory,
      passphrase: passphrase,
    );
    if (next case StartupLocked(
      reason: DatabaseKeyFailure.envelopeUnreadable,
    )) {
      return false;
    }
    if (mounted) setState(() => _startup = next);
    return true;
  }

  Future<bool> _recoverWithPassphrase(
    StartupNeedsPassphrase needs,
    String recoveryKey,
    String passphrase,
  ) async {
    final Startup next;
    try {
      next = await recoverWithPassphrase(
        needs.directory,
        recoveryKey,
        passphrase,
      );
    } on EnvelopeException {
      return false;
    }
    if (mounted) setState(() => _startup = next);
    return true;
  }

  Future<bool> _recover(StartupLocked locked, String recoveryKey) async {
    final Startup next;
    try {
      next = await recover(locked.manager, recoveryKey);
    } on EnvelopeException {
      return false;
    }
    if (mounted) setState(() => _startup = next);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final Startup startup = _startup;
    return ProviderScope(
      // A new container per startup: the override count changes with it.
      key: ObjectKey(startup),
      overrides: [
        localSettingsProvider.overrideWithValue(widget.settings),
        if (startup is StartupReady) ...[
          databaseProvider.overrideWithValue(startup.database),
          keyManagerProvider.overrideWithValue(startup.manager),
        ],
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
          final StartupNeedsPassphrase needs => BudgetApp(
            lockable: false,
            home: PassphrasePage(
              firstRun: needs.firstRun,
              canRecover: needs.canRecover,
              onSubmit: (String passphrase) =>
                  _openWithPassphrase(needs, passphrase),
              onRecover: (String recoveryKey, String passphrase) =>
                  _recoverWithPassphrase(needs, recoveryKey, passphrase),
              onStartOver: () => _startOver(
                StartupLocked(
                  DatabaseKeyFailure.envelopeUnreadable,
                  DatabaseKeyManager(
                    directory: needs.directory,
                    keyStore: PassphraseKeyStore(
                      directory: needs.directory,
                      passphrase: '',
                    ),
                  ),
                ),
              ),
            ),
          ),
          final StartupLocked locked => BudgetApp(
            lockable: false,
            home: DecryptionFailurePage(
              canRecover: locked.manager.hasRecoveryKey,
              onRecover: (String key) => _recover(locked, key),
              onRestore: (BackupContents backup, String key) =>
                  _restore(locked, backup, key),
              onStartOver: () => _startOver(locked),
            ),
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
  const BudgetApp({required this.home, this.lockable = true, super.key});

  final Widget home;

  /// False where no database is open.
  final bool lockable;

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
          child: LaunchCurtain(
            child: lockable
                ? AppLockGate(child: child ?? const SizedBox.shrink())
                : child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: home,
    );
  }
}
