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
import 'package:sielto/domain/schedule/working_days.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/feed/feed_page.dart';
import 'package:sielto/features/feed/feed_window.dart';
import 'package:sielto/features/periods/period_service.dart';
import 'package:sielto/features/space/period_ledger.dart';

/// Feed scrolling: the selected period follows the list, and the window
/// widens while records or periods lie beyond.
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
                : const FeedPage(),
          ),
        ),
      ),
    ),
  );

  testWidgets('scrolling reaches the last period and the window stops', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    late Repositories repos;
    late Space space;
    await tester.runAsync(() async {
      final SpaceClock clock = SpaceClock(timezone: 'UTC');
      final CalendarDate today = clock.today();
      repos = Repositories(db: db, clock: clock, userId: 'user-1');
      space = await repos.spaces.create(
        title: 'Household',
        spaceType: SpaceType.family,
        budgetMode: BudgetMode.incomeDriven,
        ownerId: 'user-1',
        timezone: 'UTC',
        currencyCode: 'EUR',
      );
      await repos.incomeRules.createFirstAsAnchor(
        spaceId: space.id,
        mode: BudgetMode.incomeDriven,
        title: 'Salary',
        amount: Decimal.parse('1000'),
        scheduleType: ScheduleType.fixedDate,
        fixedDay: 1,
      );
      await PeriodService(
        repos: repos,
        calendar: WorkingDayCalendar.weekendsOnly(),
      ).refresh(space, today);
      for (int i = 0; i < 20; i++) {
        await repos.payments.create(
          spaceId: space.id,
          title: 'P$i',
          amount: Decimal.parse('10'),
          dueDate: today.addDays(i * 3),
          expenseType: ExpenseType.variable,
        );
      }
      await tester.pumpWidget(harness());
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    final BuildContext ctx = tester.element(find.byType(FeedPage));
    final ProviderContainer c = ProviderScope.containerOf(ctx);
    for (int round = 0; round < 4; round++) {
      await tester.runAsync(() async {
        await tester.fling(
          find.byType(Scrollable).first,
          const Offset(0, -3000),
          3000,
        );
        for (int i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
    }

    expect(
      c.read(selectedPeriodProvider)?.id,
      c.read(incomePeriodsProvider).last.id,
    );
    final FeedWindow window = c.read(feedWindowProvider);
    final CalendarDate today = SpaceClock(timezone: 'UTC').today();
    expect(window.from, today.addMonths(-FeedWindow.stepMonths));
    expect(
      window.to.isAfter(
        today.addMonths(
          PeriodService.maxReachMonths + PeriodService.horizonStepMonths,
        ),
      ),
      isFalse,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  for (final FeedDensity density in FeedDensity.values) {
    testWidgets('scrolling down keeps loading incomes, ${density.name}', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await settings.setFeedDensity(density);
      await tester.runAsync(() async {
        final SpaceClock clock = SpaceClock(timezone: 'UTC');
        final CalendarDate today = clock.today();
        final Repositories repos = Repositories(
          db: db,
          clock: clock,
          userId: 'user-1',
        );
        final Space space = await repos.spaces.create(
          title: 'Household',
          spaceType: SpaceType.family,
          budgetMode: BudgetMode.incomeDriven,
          ownerId: 'user-1',
          timezone: 'UTC',
          currencyCode: 'EUR',
        );
        await repos.incomeRules.createFirstAsAnchor(
          spaceId: space.id,
          mode: BudgetMode.incomeDriven,
          title: 'Salary',
          amount: Decimal.parse('1000'),
          scheduleType: ScheduleType.fixedDate,
          fixedDay: 1,
        );
        await PeriodService(
          repos: repos,
          calendar: WorkingDayCalendar.weekendsOnly(),
        ).refresh(space, today);
        await tester.pumpWidget(harness());
        for (int i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      final ProviderContainer c = ProviderScope.containerOf(
        tester.element(find.byType(FeedPage)),
      );
      final CalendarDate today = SpaceClock(timezone: 'UTC').today();
      for (int round = 0; round < 8; round++) {
        await tester.runAsync(() async {
          await tester.fling(
            find.byType(Scrollable).first,
            const Offset(0, -3000),
            3000,
          );
          for (int i = 0; i < 20; i++) {
            await tester.pump(const Duration(milliseconds: 50));
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
      }

      expect(
        c.read(feedWindowProvider).to.isAfter(today.addMonths(12)),
        isTrue,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    });
  }
}
