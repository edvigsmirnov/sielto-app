import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/app/startup.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/time/space_clock.dart';
import 'package:sielto/domain/schedule/working_days.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/calendar/calendar_scope.dart';
import 'package:sielto/features/calendar/day_marks.dart';
import 'package:sielto/features/periods/holiday_service.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SpaceClock.initialize();
  });

  test(
    'a grid at the turn of the year marks the next year\'s holidays',
    () async {
      final AppDatabase db = inMemoryDatabase();
      addTearDown(db.close);
      final Space space =
          await Repositories(
            db: db,
            clock: SpaceClock(timezone: 'UTC'),
            userId: 'user-1',
          ).spaces.create(
            title: 'Home',
            spaceType: SpaceType.personal,
            budgetMode: BudgetMode.flow,
            ownerId: 'user-1',
            timezone: 'UTC',
            currencyCode: 'EUR',
          );
      final CalendarDate newYear = CalendarDate(2027, 1, 1);
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          currentSpaceProvider.overrideWithValue(space),
          spacePeriodsProvider.overrideWith(
            (Ref ref) =>
                Stream<List<BudgetPeriod>>.value(const <BudgetPeriod>[]),
          ),
          highLoadThresholdProvider.overrideWith((Ref ref) async => null),
          // Each year knows only its own holidays.
          calendarForYearProvider.overrideWith(
            (Ref ref, int year) async => ResolvedCalendar(
              calendar: WorkingDayCalendar(
                holidays: <CalendarDate>{if (year == 2027) newYear},
              ),
              missingYears: const <int>{},
              countryCode: 'DE',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(selectedDateProvider.notifier)
          .select(CalendarDate(2026, 12, 15));

      container.listen(dayMarksProvider(CalendarView.month), (_, _) {});
      final DayMarks marks = await container.read(
        dayMarksProvider(CalendarView.month).future,
      );
      expect(marks[newYear].isHoliday, isTrue);
    },
  );
}
