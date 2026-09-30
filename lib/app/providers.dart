import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/backup/backup_service.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/analytics_repository.dart';
import 'package:sielto/core/db/repositories/budget_period_repository.dart';
import 'package:sielto/core/db/repositories/calendar_repository.dart';
import 'package:sielto/core/db/repositories/category_repository.dart';
import 'package:sielto/core/db/repositories/holiday_repository.dart';
import 'package:sielto/core/db/repositories/income_repository.dart';
import 'package:sielto/core/db/repositories/payment_repository.dart';
import 'package:sielto/core/db/repositories/space_repository.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/time/space_clock.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/periods/holiday_service.dart';
import 'package:sielto/features/periods/period_service.dart';

/// Overridden at startup once the database is open.
final Provider<AppDatabase> databaseProvider = Provider<AppDatabase>(
  (Ref ref) => throw StateError('databaseProvider was not overridden'),
);

/// Every repository. The clock is UTC: repositories only stamp writes. "Today"
/// comes from [spaceClockProvider].
class Repositories {
  Repositories({
    required this.db,
    required SpaceClock clock,
    required String userId,
  }) : spaces = SpaceRepository(db: db, clock: clock),
       payments = PaymentRepository(db: db, clock: clock, userId: userId),
       incomes = IncomeRepository(db: db, clock: clock, userId: userId),
       incomeRules = IncomeRuleRepository(db: db, clock: clock, userId: userId),
       periods = BudgetPeriodRepository(db: db, clock: clock, userId: userId),
       holidays = HolidayRepository(db: db, clock: clock),
       customDays = CustomNonWorkingDayRepository(db: db, clock: clock),
       calendar = CalendarRepository(db: db),
       analytics = AnalyticsRepository(db: db),
       backup = BackupService(db: db, clock: clock, userId: userId) {
    categories = CategoryRepository(
      db: db,
      clock: clock,
      userId: userId,
      payments: payments,
    );
  }

  final AppDatabase db;
  final SpaceRepository spaces;
  final PaymentRepository payments;
  final IncomeRepository incomes;
  final IncomeRuleRepository incomeRules;
  final BudgetPeriodRepository periods;

  final HolidayRepository holidays;
  final CustomNonWorkingDayRepository customDays;

  final CalendarRepository calendar;
  final AnalyticsRepository analytics;
  final BackupService backup;

  late final CategoryRepository categories;
}

final Provider<Repositories> repositoriesProvider = Provider<Repositories>(
  (Ref ref) => Repositories(
    db: ref.watch(databaseProvider),
    clock: SpaceClock(timezone: 'UTC'),
    userId: ref.watch(userIdProvider),
  ),
);

final StreamProvider<List<Space>> spaceListProvider =
    StreamProvider<List<Space>>(
      (Ref ref) => ref.watch(repositoriesProvider).spaces.watchAll(),
    );

final StreamProvider<List<Space>> archivedSpacesProvider =
    StreamProvider<List<Space>>(
      (Ref ref) => ref.watch(repositoriesProvider).spaces.watchArchived(),
    );

/// Persisted across launches.
class CurrentSpaceIdController extends Notifier<String?> {
  @override
  String? build() => ref.watch(localSettingsProvider).currentSpaceId;

  Future<void> select(String? spaceId) async {
    await ref.read(localSettingsProvider).setCurrentSpaceId(spaceId);
    state = spaceId;
  }
}

final NotifierProvider<CurrentSpaceIdController, String?>
currentSpaceIdProvider = NotifierProvider<CurrentSpaceIdController, String?>(
  CurrentSpaceIdController.new,
);

/// The stored selection, else the first Space, else null (onboarding).
final Provider<AsyncValue<Space?>> resolvedSpaceProvider =
    Provider<AsyncValue<Space?>>((Ref ref) {
      final String? selected = ref.watch(currentSpaceIdProvider);
      return ref.watch(spaceListProvider).whenData((List<Space> spaces) {
        if (spaces.isEmpty) return null;
        for (final Space space in spaces) {
          if (space.id == selected) return space;
        }
        return spaces.first;
      });
    });

/// The open Space, or null. Root-level: never scope it with an override.
final Provider<Space?> currentSpaceProvider = Provider<Space?>(
  (Ref ref) => ref.watch(resolvedSpaceProvider).value,
);

/// UTC before a Space exists. Rebuilds when the Space's day turns, so every
/// "today" read through a watch follows it.
final Provider<SpaceClock> spaceClockProvider = Provider<SpaceClock>((Ref ref) {
  final Space? space = ref.watch(currentSpaceProvider);
  final SpaceClock clock = SpaceClock(timezone: space?.timezone ?? 'UTC');
  final CalendarDate today = clock.today();

  final Timer midnight = Timer(
    clock.endOfDayUtc(today).difference(clock.nowUtc()),
    ref.invalidateSelf,
  );
  // The timer does not run while the device sleeps.
  final AppLifecycleListener resume = AppLifecycleListener(
    onResume: () {
      if (clock.today() != today) ref.invalidateSelf();
    },
  );
  ref.onDispose(() {
    midnight.cancel();
    resume.dispose();
  });
  return clock;
});

/// Today in the open Space's timezone.
final Provider<CalendarDate> todayProvider = Provider<CalendarDate>(
  (Ref ref) => ref.watch(spaceClockProvider).today(),
);

final Provider<HolidayService> holidayServiceProvider =
    Provider<HolidayService>((Ref ref) {
      final Repositories repos = ref.watch(repositoriesProvider);
      return HolidayService(
        holidays: repos.holidays,
        customDays: repos.customDays,
      );
    });

final StreamProvider<List<CustomNonWorkingDay>> customNonWorkingDaysProvider =
    StreamProvider<List<CustomNonWorkingDay>>(
      (Ref ref) => ref.watch(repositoriesProvider).customDays.watchAll(),
    );

/// Non-working days for income dates. Country: the Space's, else the default,
/// else none.
final FutureProvider<ResolvedCalendar> resolvedCalendarProvider =
    FutureProvider<ResolvedCalendar>((Ref ref) {
      final CalendarDate today = ref.watch(spaceClockProvider).today();
      // Every year periods can reach.
      return _resolveCalendar(ref, <int>{
        for (
          int y = today.year;
          y <= today.addMonths(PeriodService.maxReachMonths).year;
          y++
        )
          y,
      });
    });

/// The calendar for one year, for browsing outside the materialisation years.
/// Type inferred: `flutter_riverpod` does not export `FutureProviderFamily`.
final calendarForYearProvider = FutureProvider.family<ResolvedCalendar, int>(
  (Ref ref, int year) => _resolveCalendar(ref, <int>{year}),
);

Future<ResolvedCalendar> _resolveCalendar(Ref ref, Set<int> years) {
  final Space? space = ref.watch(currentSpaceProvider);

  // Watched through the controllers, which notify on change.
  final String? defaultCountry = ref.watch(defaultCountryProvider);
  final String? region = ref.watch(holidayRegionProvider);
  final bool consented = ref.watch(holidayConsentProvider) ?? false;
  final bool offline = ref.watch(offlineModeProvider);

  ref.watch(customNonWorkingDaysProvider);

  return ref
      .watch(holidayServiceProvider)
      .resolve(
        countryCode: space?.countryCode ?? defaultCountry,
        region: space?.countryCode == null ? region : null,
        years: years,
        mayFetch: !offline && consented,
      );
}

/// How far ahead periods must reach. Null until asked; only moves forward.
class PeriodReachController extends Notifier<CalendarDate?> {
  @override
  CalendarDate? build() {
    ref.watch(currentSpaceIdProvider);
    return null;
  }

  void reach(CalendarDate date) {
    final CalendarDate? current = state;
    if (current == null || date.isAfter(current)) state = date;
  }
}

final NotifierProvider<PeriodReachController, CalendarDate?>
periodReachProvider = NotifierProvider<PeriodReachController, CalendarDate?>(
  PeriodReachController.new,
);

/// Recomputes periods and future occurrences for the open Space.
final FutureProvider<PeriodRefresh> periodRefreshProvider =
    FutureProvider<PeriodRefresh>((Ref ref) async {
      final Space? space = ref.watch(currentSpaceProvider);
      if (space == null) return const PeriodRefresh();

      final ResolvedCalendar resolved = await ref.watch(
        resolvedCalendarProvider.future,
      );
      return PeriodService(
        repos: ref.watch(repositoriesProvider),
        calendar: resolved.calendar,
        missingHolidayYears: resolved.missingYears,
      ).refresh(
        space,
        ref.watch(spaceClockProvider).today(),
        until: ref.watch(periodReachProvider),
      );
    });

final StreamProvider<List<BudgetPeriod>> spacePeriodsProvider =
    StreamProvider<List<BudgetPeriod>>((Ref ref) {
      final Space? space = ref.watch(currentSpaceProvider);
      if (space == null) return const Stream<List<BudgetPeriod>>.empty();
      return ref.watch(repositoriesProvider).periods.watchInSpace(space.id);
    });

/// The open Space. Throws when none is open.
extension CurrentSpaceX on WidgetRef {
  Space get space =>
      watch(currentSpaceProvider) ?? (throw StateError('no Space is open'));
}
