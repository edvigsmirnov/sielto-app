import 'dart:convert';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/app/startup.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/l10n/app_locales.dart';
import 'package:sielto/core/settings/local_settings.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_theme.dart';
import 'package:sielto/core/time/space_clock.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/analytics/analytics_page.dart';
import 'package:sielto/features/calendar/calendar_page.dart';
import 'package:sielto/features/categories/categories_page.dart';
import 'package:sielto/features/dashboard/dashboard_page.dart';
import 'package:sielto/features/devices/join_page.dart';
import 'package:sielto/features/feed/feed_page.dart';
import 'package:sielto/features/incomes/income_form_page.dart';
import 'package:sielto/features/members/join_space_page.dart';
import 'package:sielto/features/onboarding/onboarding_page.dart';
import 'package:sielto/features/onboarding/welcome_page.dart';
import 'package:sielto/features/payments/payment_form_page.dart';
import 'package:sielto/features/security/recovery_key.dart';
import 'package:sielto/features/settings/settings_page.dart';
import 'package:sielto/features/settings/space_settings_page.dart';
import 'package:sielto/features/spaces/space_form_page.dart';

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
    await repos.incomeRules.createFirstAsAnchor(
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

  Widget harness(Widget page, ThemeData theme, double scale) =>
      EasyLocalization(
        supportedLocales: AppLocales.supported,
        path: AppLocales.path,
        fallbackLocale: AppLocales.fallback,
        startLocale: AppLocales.en,
        saveLocale: false,
        ignorePluralRules: false,
        assetLoader: const _FileAssetLoader(),
        child: ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            localSettingsProvider.overrideWithValue(settings),
            recoveryKeySetProvider.overrideWithBuild((_, _) => true),
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
      (WidgetTester t) => t.tap(find.text(label));
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
  };

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
    for (final (String, ThemeData) theme in <(String, ThemeData)>[
      ('light', SageTheme.light),
      ('dark', SageTheme.dark),
    ]) {
      for (final double scale in <double>[1, 2]) {
        testWidgets('${page.key}, ${theme.$1}, x$scale', (
          WidgetTester tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
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
            await page.value.before?.call(tester);
            await tester.pumpWidget(
              harness(page.value.page(), theme.$2, scale),
            );
            await settle();
            if (page.value.then case final then?) {
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
              if (await g.evaluate(tester) case final Evaluation e
                  when !e.passed)
                e.reason!,
          ];
          expect(misses, isEmpty, reason: misses.join('\n'));
          handle.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(Duration.zero);
        });
      }
    }
  }
}
