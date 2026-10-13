import 'dart:convert';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/app/startup.dart';
import 'package:sielto/core/backup/backup_service.dart';
import 'package:sielto/core/crypto/key_store.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/l10n/app_locales.dart';
import 'package:sielto/core/l10n/pseudo_asset_loader.dart';
import 'package:sielto/core/l10n/pseudolocalize.dart';
import 'package:sielto/core/settings/local_settings.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_theme.dart';
import 'package:sielto/core/time/space_clock.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/analytics/analytics_page.dart';
import 'package:sielto/features/backup/backup_page.dart';
import 'package:sielto/features/calendar/calendar_page.dart';
import 'package:sielto/features/categories/categories_page.dart';
import 'package:sielto/features/categories/category_form_page.dart';
import 'package:sielto/features/dashboard/dashboard_page.dart';
import 'package:sielto/features/devices/join_page.dart';
import 'package:sielto/features/feed/feed_page.dart';
import 'package:sielto/features/incomes/income_form_page.dart';
import 'package:sielto/features/incomes/income_rule_form_page.dart';
import 'package:sielto/features/incomes/income_rules_page.dart';
import 'package:sielto/features/members/join_space_page.dart';
import 'package:sielto/features/onboarding/onboarding_page.dart';
import 'package:sielto/features/onboarding/welcome_page.dart';
import 'package:sielto/features/overdue/overdue.dart';
import 'package:sielto/features/payments/payment_form_page.dart';
import 'package:sielto/features/security/decryption_failure_page.dart';
import 'package:sielto/features/security/passphrase_page.dart';
import 'package:sielto/features/security/recovery_key.dart';
import 'package:sielto/features/security/security_page.dart';
import 'package:sielto/features/settings/holidays_page.dart';
import 'package:sielto/features/settings/settings_page.dart';
import 'package:sielto/features/settings/space_settings_page.dart';
import 'package:sielto/features/shell/main_shell.dart';
import 'package:sielto/features/spaces/space_form_page.dart';
import 'package:sielto/features/spaces/space_switcher_sheet.dart';

/// Tap targets, labels and contrast on every main screen, in both themes and
/// at text scale 2.0.
class _FileAssetLoader extends AssetLoader {
  const _FileAssetLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    final File file = File('$path/${locale.languageCode}.json');
    return json.decode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

void main() {
  late AppDatabase db;
  late LocalSettings settings;
  late Space space;
  late IncomeRecurrenceRule salary;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
    SpaceClock.initialize();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    settings = await LocalSettings.load();
    db = inMemoryDatabase();
    final Repositories repos = Repositories(
      db: db,
      clock: SpaceClock(timezone: 'UTC'),
      userId: 'user-1',
    );
    space = await repos.spaces.create(
      title: 'Household',
      spaceType: SpaceType.family,
      budgetMode: BudgetMode.incomeDriven,
      ownerId: 'user-1',
      timezone: 'Europe/Berlin',
      currencyCode: 'EUR',
    );
    salary = await repos.incomeRules.createFirstAsAnchor(
      spaceId: space.id,
      mode: BudgetMode.incomeDriven,
      title: 'Salary',
      amount: Decimal.parse('1000'),
      scheduleType: ScheduleType.fixedDate,
      fixedDay: 5,
    );
    final today = SpaceClock(timezone: 'Europe/Berlin').today();
    await repos.payments.create(
      spaceId: space.id,
      title: 'Groceries',
      amount: Decimal.parse('22.50'),
      dueDate: today,
      isPaid: true,
      expenseType: ExpenseType.variable,
    );
    await repos.payments.create(
      spaceId: space.id,
      title: 'Phone',
      amount: Decimal.parse('15'),
      dueDate: today.addDays(-2),
      expenseType: ExpenseType.mandatory,
      notes: 'Ask about the new plan',
    );
    await repos.payments.create(
      spaceId: space.id,
      title: 'Rent',
      amount: Decimal.parse('400'),
      dueDate: today.addDays(3),
      expenseType: ExpenseType.mandatory,
    );
  });

  tearDown(() => db.close());

  Widget harness(
    Widget page,
    ThemeData theme,
    double scale, {
    Locale locale = AppLocales.en,
  }) => EasyLocalization(
    supportedLocales: AppLocales.supported,
    path: AppLocales.path,
    fallbackLocale: AppLocales.fallback,
    startLocale: locale,
    saveLocale: false,
    ignorePluralRules: false,
    assetLoader: const PseudoAssetLoader(base: _FileAssetLoader()),
    child: ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(settings),
        recoveryKeySetProvider.overrideWithBuild((_, _) => true),
        keyManagerProvider.overrideWithValue(
          DatabaseKeyManager(directory: Directory.systemTemp),
        ),
      ],
      child: Builder(
        builder: (BuildContext context) => MaterialApp(
          theme: theme,
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? _) =>
                ref.watch(currentSpaceProvider) == null
                ? const SizedBox.shrink()
                : page,
          ),
        ),
      ),
    ),
  );

  Future<void> Function(WidgetTester) tap(String label) =>
      (WidgetTester t) => t.tap(
        find.byWidgetPredicate(
          (Widget w) =>
              w is Text && (w.data == label || w.data == pseudolocalize(label)),
        ),
      );
  Future<void> Function(WidgetTester) density(FeedDensity d) =>
      (WidgetTester _) => settings.setFeedDensity(d);

  final Map<
    String,
    ({
      Widget Function() page,
      Future<void> Function(WidgetTester)? before,
      Future<void> Function(WidgetTester)? then,
    })
  >
  pages = {
    'dashboard': (page: () => const DashboardPage(), before: null, then: null),
    'feed': (page: () => const FeedPage(), before: null, then: null),
    'feed, compact': (
      page: () => const FeedPage(),
      before: density(FeedDensity.compact),
      then: null,
    ),
    'feed, spacious': (
      page: () => const FeedPage(),
      before: density(FeedDensity.spacious),
      then: null,
    ),
    'calendar month': (
      page: () => const CalendarPage(),
      before: null,
      then: null,
    ),
    'calendar day': (
      page: () => const CalendarPage(),
      before: null,
      then: tap('Day'),
    ),
    'calendar week': (
      page: () => const CalendarPage(),
      before: null,
      then: tap('Week'),
    ),
    'calendar year': (
      page: () => const CalendarPage(),
      before: null,
      then: tap('Year'),
    ),
    'analytics': (page: () => const AnalyticsPage(), before: null, then: null),
    'settings': (page: () => const SettingsPage(), before: null, then: null),
    'space settings': (
      page: () => SpaceSettingsPage(space: space),
      before: null,
      then: null,
    ),
    'categories': (
      page: () => const CategoriesPage(),
      before: null,
      then: null,
    ),
    'payment form': (
      page: () => const PaymentFormPage(),
      before: null,
      then: null,
    ),
    'income form': (
      page: () => const IncomeFormPage(),
      before: null,
      then: null,
    ),
    'space form': (page: () => const SpaceFormPage(), before: null, then: null),
    'welcome': (
      page: () => WelcomePage(onStart: (Offset _) {}, onJoin: () {}),
      before: null,
      then: null,
    ),
    'onboarding': (
      page: () => const OnboardingPage(),
      before: null,
      then: null,
    ),
    'join device': (page: () => const JoinPage(), before: null, then: null),
    'join space': (page: () => const JoinSpacePage(), before: null, then: null),
    'spaces': (page: () => const SpacesPage(), before: null, then: null),
    'backup': (page: () => const BackupPage(), before: null, then: null),
    'security': (page: () => const SecurityPage(), before: null, then: null),
    'recovery key': (
      page: () => const RecoveryKeyPage(),
      before: null,
      then: null,
    ),
    'holidays': (page: () => const HolidaysPage(), before: null, then: null),
    'category form': (
      page: () => const CategoryFormPage(),
      before: null,
      then: null,
    ),
    'regular incomes': (
      page: () => const IncomeRulesPage(),
      before: null,
      then: null,
    ),
    'regular income form': (
      page: () => IncomeRuleFormPage(rule: salary),
      before: null,
      then: null,
    ),
    'overdue': (
      page: () => OverduePage(
        money: MoneyFormat(locale: 'en', currencyCode: 'EUR'),
      ),
      before: null,
      then: null,
    ),
    'password': (
      page: () => PassphrasePage(
        firstRun: false,
        canRecover: true,
        onSubmit: (String _) async => true,
        onRecover: (String _, String _) async => true,
        onStartOver: () async {},
      ),
      before: null,
      then: null,
    ),
    'decryption failure': (
      page: () => DecryptionFailurePage(
        canRecover: true,
        onRecover: (String _) async => true,
        onRestore: (BackupContents _, String _) async {},
        onStartOver: () async {},
      ),
      before: null,
      then: null,
    ),
  };

  /// [size] is the window in logical pixels; [platform] sets desktop input.
  void guidelines(
    String name,
    Widget Function() page, {
    Future<void> Function(WidgetTester)? before,
    Future<void> Function(WidgetTester)? then,
    Size size = const Size(1080 / 2.625, 2400 / 2.625),
    TargetPlatform? platform,
  }) {
    // Pseudo-accented text, a third longer, checks for overflow.
    for (final (String, ThemeData, double, Locale) run
        in <(String, ThemeData, double, Locale)>[
          ('light, x1', SageTheme.light, 1, AppLocales.en),
          ('light, x2', SageTheme.light, 2, AppLocales.en),
          ('dark, x1', SageTheme.dark, 1, AppLocales.en),
          ('dark, x2', SageTheme.dark, 2, AppLocales.en),
          ('dark, pseudo', SageTheme.dark, 1, AppLocales.pseudo),
        ]) {
      final (String label, ThemeData theme, double scale, Locale locale) = run;
      testWidgets('$name, $label', (WidgetTester tester) async {
        debugDefaultTargetPlatformOverride = platform;
        tester.view.physicalSize = size * 2.625;
        tester.view.devicePixelRatio = 2.625;
        addTearDown(tester.view.reset);
        final SemanticsHandle handle = tester.ensureSemantics();
        Future<void> settle() async {
          for (int i = 0; i < 20; i++) {
            await tester.pump(const Duration(milliseconds: 50));
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        }

        await tester.runAsync(() async {
          await before?.call(tester);
          await tester.pumpWidget(
            harness(page(), theme, scale, locale: locale),
          );
          await settle();
          if (then != null) {
            await then(tester);
            await settle();
          }
        });
        final List<String> misses = <String>[
          for (final AccessibilityGuideline g in <AccessibilityGuideline>[
            androidTapTargetGuideline,
            labeledTapTargetGuideline,
            textContrastGuideline,
          ])
            if (await g.evaluate(tester) case final Evaluation e when !e.passed)
              e.reason!,
        ];
        handle.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(Duration.zero);
        debugDefaultTargetPlatformOverride = null;
        expect(misses, isEmpty, reason: misses.join('\n'));
      });
    }
  }

  for (final MapEntry<
        String,
        ({
          Widget Function() page,
          Future<void> Function(WidgetTester)? before,
          Future<void> Function(WidgetTester)? then,
        })
      >
      page
      in pages.entries) {
    guidelines(
      page.key,
      page.value.page,
      before: page.value.before,
      then: page.value.then,
    );
  }

  // Desktop: the shell's two wide layouts, the Feed table and its search
  // panel, and the setup cards.
  const Size desktop = Size(1600, 1000);
  Future<void> oneColumn(WidgetTester _) =>
      settings.setThreeColumns(value: false);
  Future<void> openSearch(WidgetTester t) async {
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyF);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  }

  guidelines(
    'desktop, three columns',
    () => const MainShell(),
    size: desktop,
    platform: TargetPlatform.linux,
  );
  for (final (String, Size) wide in <(String, Size)>[
    ('desktop', desktop),
    // Under the three-column breakpoint.
    ('desktop, narrow', const Size(1000, 800)),
  ]) {
    guidelines(
      '${wide.$1}, one column',
      () => const MainShell(),
      before: oneColumn,
      size: wide.$2,
      platform: TargetPlatform.linux,
    );
  }
  guidelines(
    'desktop, Feed search',
    () => const MainShell(),
    then: openSearch,
    size: desktop,
    platform: TargetPlatform.linux,
  );
  guidelines(
    'desktop, onboarding',
    () => const OnboardingPage(),
    size: desktop,
    platform: TargetPlatform.linux,
  );
  guidelines(
    'desktop, join device',
    () => const JoinPage(),
    size: desktop,
    platform: TargetPlatform.linux,
  );
}
