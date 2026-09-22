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
import 'package:sielto/features/dashboard/dashboard_page.dart';
import 'package:sielto/features/space/period_ledger.dart';

/// The Regular-income Dashboard over a real database, with records written
/// while a form covers it. The first anchor has no period until the refresh
/// creates one, and nothing but the Dashboard was there to trigger it.
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
    await repos.payments.create(
      spaceId: space.id,
      title: 'Groceries',
      amount: Decimal.parse('22.50'),
      // A date in the current month, whenever the suite runs: the screen opens
      // on today, and a fixture pinned to 2026 would fall outside the grid.
      dueDate: SpaceClock(timezone: 'Europe/Berlin').today(),
      isPaid: true,
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
        // No Space override: with nothing stored, `resolvedSpaceProvider`
        // falls back to the first Space on the device, which is the fixture.
      ],
      child: Builder(
        builder: (BuildContext context) => MaterialApp(
          theme: SageTheme.light,
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          // Gated on the Space, as main.dart gates the shell: `ref.space`
          // throws where there is none, which is a routing mistake rather than
          // a state a screen has to handle.
          home: Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? _) =>
                ref.watch(currentSpaceProvider) == null
                ? const SizedBox.shrink()
                : const DashboardPage(),
          ),
        ),
      ),
    ),
  );

  /// Tears the tree down inside the test body.
  ///
  /// Disposing the `ProviderScope` cancels drift's query streams, and each
  /// cancellation posts a zero-duration timer. Left to the framework's own
  /// teardown those timers are still pending when it checks, and the test
  /// fails with "A Timer is still pending" instead of its real result.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  /// Pumps until the streams behind the screen have emitted.
  ///
  /// `runAsync` because the drift streams need a real event loop, and repeated
  /// `pump` rather than `pumpAndSettle` because a screen stuck on a spinner
  /// never settles — it would report a timeout instead of the real failure.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(harness());
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    });
  }

  Future<void> wait(WidgetTester tester, int n) async {
    for (int i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> covered(
    WidgetTester tester,
    Future<void> Function(Repositories repos) write,
  ) async {
    await settle(tester);
    final BuildContext ctx = tester.element(find.byType(DashboardPage));
    final ProviderContainer c = ProviderScope.containerOf(ctx);
    await tester.runAsync(() async {
      await wait(tester, 10);
      Navigator.of(ctx)
          .push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
      await wait(tester, 20);
      await write(c.read(repositoriesProvider));
      await wait(tester, 5);
      c.invalidate(periodRefreshProvider);
      Navigator.of(ctx).pop();
      await wait(tester, 30);
    });
    expect(c.read(periodLedgerProvider).hasValue, isTrue);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await unmount(tester);
  }

  Future<void> anchor(Repositories repos) =>
      repos.incomeRules.createFirstAsAnchor(
        spaceId: space.id,
        mode: BudgetMode.incomeDriven,
        title: 'Salary',
        amount: Decimal.parse('1000'),
        scheduleType: ScheduleType.fixedDate,
        fixedDay: 5,
      );

  testWidgets('first regular income', (WidgetTester tester) async {
    await covered(tester, anchor);
  });

  testWidgets('one-off income with an anchor present', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final Repositories repos = Repositories(
        db: db,
        clock: SpaceClock(timezone: 'UTC'),
        userId: 'user-1',
      );
      await anchor(repos);
    });
    await covered(
      tester,
      (Repositories repos) => repos.incomes.create(
        spaceId: space.id,
        title: 'Bonus',
        expectedDate: SpaceClock(timezone: 'Europe/Berlin').today(),
        amount: Decimal.parse('50'),
      ),
    );
  });

  testWidgets('second regular income', (WidgetTester tester) async {
    await tester.runAsync(() async {
      final Repositories repos = Repositories(
        db: db,
        clock: SpaceClock(timezone: 'UTC'),
        userId: 'user-1',
      );
      await anchor(repos);
    });
    await covered(
      tester,
      (Repositories repos) => repos.incomeRules.create(
        spaceId: space.id,
        title: 'Side',
        amount: Decimal.parse('100'),
        scheduleType: ScheduleType.fixedDate,
        fixedDay: 20,
      ),
    );
  });
}
