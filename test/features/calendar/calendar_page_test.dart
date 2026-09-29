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
import 'package:sielto/features/calendar/calendar_page.dart';
import 'package:sielto/features/calendar/month_view.dart';
import 'package:sielto/features/calendar/week_view.dart';
import 'package:sielto/features/calendar/year_view.dart';

/// Calendar over a real database and the real provider graph.
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
      budgetMode: BudgetMode.flow,
      ownerId: 'user-1',
      timezone: 'Europe/Berlin',
      currencyCode: 'EUR',
    );
    await repos.payments.create(
      spaceId: space.id,
      title: 'Groceries',
      amount: Decimal.parse('22.50'),
      // Inside the current month, whenever the suite runs.
      dueDate: SpaceClock(timezone: 'Europe/Berlin').today(),
      expenseType: ExpenseType.variable,
    );
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
        // With nothing stored, `resolvedSpaceProvider` picks the fixture Space.
      ],
      child: Builder(
        builder: (BuildContext context) => MaterialApp(
          theme: SageTheme.light,
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          // `ref.space` throws without a Space.
          home: Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? _) =>
                ref.watch(currentSpaceProvider) == null
                ? const SizedBox.shrink()
                : const CalendarPage(),
          ),
        ),
      ),
    ),
  );

  /// Disposing the scope posts drift's cancellation timers; unmounting here
  /// lets them fire before teardown checks.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  /// Pumps until the streams have emitted. `runAsync` for drift's streams; not
  /// `pumpAndSettle`, which times out on a spinner.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(harness());
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    });
  }

  testWidgets('opens on the Month grid with the month drawn', (
    WidgetTester tester,
  ) async {
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(MonthView), findsOneWidget);
    expect(find.textContaining('23'), findsWidgets);
    await unmount(tester);
  });

  testWidgets('the switcher reaches all four scales', (
    WidgetTester tester,
  ) async {
    await settle(tester);

    for (final (String label, Type view) in const <(String, Type)>[
      ('Week', WeekView),
      ('Year', YearView),
      ('Month', MonthView),
    ]) {
      await tester.runAsync(() async {
        await tester.tap(find.text(label));
        for (int i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      });
      expect(tester.takeException(), isNull, reason: label);
      expect(find.byType(view), findsOneWidget, reason: label);
    }

    // The Day view is identified by its two totals.
    await tester.runAsync(() async {
      await tester.tap(find.text('Day'));
      for (int i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    });
    expect(tester.takeException(), isNull);
    expect(find.text('Expenses'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the arrows move the month and the label follows', (
    WidgetTester tester,
  ) async {
    await settle(tester);
    final CalendarDate today = SpaceClock(timezone: 'Europe/Berlin').today();

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Forward'));
      for (int i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    });
    expect(tester.takeException(), isNull);

    final CalendarDate next = today.firstOfMonth.addMonths(1);
    expect(
      find.textContaining(_monthName(next.month)),
      findsWidgets,
      reason: 'the navigator should name the month it moved to',
    );
    await unmount(tester);
  });
}

String _monthName(int month) => const <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
][month - 1];
