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
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/analytics/analytics_page.dart';
import 'package:sielto/features/analytics/donut_chart.dart';

/// The three Analytics levels over a real database (spec 8.2).
///
/// The repository tests cover the arithmetic; this walks the drill-down the way
/// a person does, which is the only way to catch a level that opens onto the
/// wrong slice.
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
    final Space space = await repos.spaces.create(
      title: 'Household',
      spaceType: SpaceType.family,
      budgetMode: BudgetMode.flow,
      ownerId: 'user-1',
      timezone: 'Europe/Berlin',
      currencyCode: 'EUR',
    );
    final Category food = await repos.categories.create(
      spaceId: space.id,
      title: 'Groceries',
    );
    final Category transport = await repos.categories.create(
      spaceId: space.id,
      title: 'Transport',
    );

    // Inside the current month, whenever the suite runs: the screen opens on
    // the month, and a fixture pinned to a year would fall outside the range.
    final CalendarDate today = SpaceClock(timezone: 'Europe/Berlin').today();
    Future<void> spend(String title, String amount, String? categoryId) =>
        repos.payments.create(
          spaceId: space.id,
          title: title,
          amount: Decimal.parse(amount),
          dueDate: today,
          expenseType: title == 'Rent'
              ? ExpenseType.mandatory
              : ExpenseType.variable,
          categoryId: categoryId,
        );

    await spend('Rewe', '600', food.id);
    await spend('Lidl', '380', food.id);
    await spend('Ticket', '420', transport.id);
    await spend('Rent', '900', transport.id);
  });

  tearDown(() => db.close());

  Widget harness() => EasyLocalization(
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
      ],
      child: Builder(
        builder: (BuildContext context) => MaterialApp(
          theme: SageTheme.light,
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          home: Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? _) =>
                ref.watch(currentSpaceProvider) == null
                ? const SizedBox.shrink()
                : const AnalyticsPage(),
          ),
        ),
      ),
    ),
  );

  /// See the note in calendar_page_test: disposing the scope leaves drift's
  /// stream-cancellation timers pending, and the framework's own teardown
  /// checks before they fire.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  Future<void> settle(WidgetTester tester, {bool pumpWidget = true}) =>
      tester.runAsync(() async {
        if (pumpWidget) await tester.pumpWidget(harness());
        for (int i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      });

  testWidgets('level 1 ranks the categories and draws the ring', (
    WidgetTester tester,
  ) async {
    await settle(tester);
    expect(tester.takeException(), isNull);

    expect(find.byType(DonutChart), findsOneWidget);
    // Each name appears twice — once in the ring's legend, once in the list
    // below it — so the row is the last of the two.
    expect(find.text('Transport'), findsNWidgets(2));
    final double transport = tester.getRect(find.text('Transport').last).top;
    final double groceries = tester.getRect(find.text('Groceries').last).top;
    // Transport is 1320 against Groceries' 980, so its row leads.
    expect(transport, lessThan(groceries));

    // The record count under each name, through the plural block.
    expect(find.text('2 records'), findsNWidgets(2));
    await unmount(tester);
  });

  testWidgets('the type filter re-cuts the same range', (
    WidgetTester tester,
  ) async {
    await settle(tester);
    // Only Rent is mandatory, so Groceries drops out of the list entirely.
    await tester.tap(find.text('Mandatory'));
    await settle(tester, pumpWidget: false);

    expect(tester.takeException(), isNull);
    expect(find.text('Groceries'), findsNothing);
    expect(find.text('1 record'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a category opens level 2, and level 2 opens level 3', (
    WidgetTester tester,
  ) async {
    await settle(tester);

    await tester.tap(find.text('Groceries').last);
    await settle(tester, pumpWidget: false);
    expect(tester.takeException(), isNull);
    // Level 2 groups by title inside the category, largest first.
    expect(find.text('Rewe'), findsOneWidget);
    expect(find.text('Lidl'), findsOneWidget);
    expect(
      tester.getRect(find.text('Rewe')).top,
      lessThan(tester.getRect(find.text('Lidl')).top),
    );
    // And nothing from the other category leaked in.
    expect(find.text('Ticket'), findsNothing);

    await tester.tap(find.text('Averages for the range'));
    await settle(tester, pumpWidget: false);
    expect(tester.takeException(), isNull);
    expect(find.text('Average payment in the range'), findsOneWidget);
    // 980 over two payments.
    expect(find.textContaining('490'), findsWidgets);
    await unmount(tester);
  });

  testWidgets('the range arrows move off the month and it empties', (
    WidgetTester tester,
  ) async {
    await settle(tester);
    await tester.tap(find.byTooltip('Back'));
    await settle(tester, pumpWidget: false);

    expect(tester.takeException(), isNull);
    expect(find.text('Nothing was spent in this range.'), findsOneWidget);
    await unmount(tester);
  });
}
