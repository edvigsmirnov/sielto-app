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
import 'package:sielto/features/periods/period_service.dart';

/// Feed figures for a cycle without income.
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

  testWidgets('a cycle whose income was deleted shows zero', (
    WidgetTester tester,
  ) async {
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
      for (final Income i in await repos.incomes.inSpace(space.id)) {
        await repos.incomes.softDelete(i.id);
      }
      await repos.payments.create(
        spaceId: space.id,
        title: 'Groceries',
        amount: Decimal.parse('22.50'),
        dueDate: today,
        isPaid: true,
        expenseType: ExpenseType.variable,
      );

      await tester.pumpWidget(harness());
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });

    expect(find.text('Left to spend'), findsOneWidget);
    expect(find.text('€0.00'), findsWidgets);
    expect(find.text('—'), findsNothing);
    expect(find.text('Not covered'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
