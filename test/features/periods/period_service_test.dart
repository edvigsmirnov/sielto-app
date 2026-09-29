import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/app/startup.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/income_repository.dart';
import 'package:sielto/core/time/space_clock.dart';
import 'package:sielto/domain/schedule/working_days.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/periods/period_service.dart';

CalendarDate d(String iso) => CalendarDate.parse(iso);
Decimal m(String v) => Decimal.parse(v);

/// Closed periods stay; open ones move in place; received incomes never move.
void main() {
  late AppDatabase db;
  late Repositories repos;
  late PeriodService service;
  late Space space;

  SpaceClock.initialize();
  final SpaceClock clock = SpaceClock(
    timezone: 'UTC',
    now: () => DateTime.utc(2026, 3, 10, 12),
  );
  final CalendarDate today = d('2026-03-10');

  setUp(() async {
    db = inMemoryDatabase();
    repos = Repositories(db: db, clock: clock, userId: 'tester');
    service = PeriodService(
      repos: repos,
      calendar: WorkingDayCalendar.weekendsOnly(),
    );
    space = await repos.spaces.create(
      title: 'Family',
      spaceType: SpaceType.family,
      budgetMode: BudgetMode.incomeDriven,
      ownerId: 'tester',
      timezone: 'UTC',
      currencyCode: 'EUR',
    );
  });

  tearDown(() => db.close());

  Future<IncomeRecurrenceRule> anchorOn(
    int day, {
    String title = 'Salary',
    String? amount = '3000',
  }) => repos.incomeRules.create(
    spaceId: space.id,
    title: title,
    scheduleType: ScheduleType.fixedDate,
    fixedDay: day,
    amount: amount == null ? null : m(amount),
    isAnchor: true,
  );

  Future<List<BudgetPeriod>> periods() =>
      repos.periods.incomeDrivenIn(space.id);

  group('with no anchor', () {
    test('a Space with no income at all is a valid state', () async {
      final PeriodRefresh result = await service.refresh(space, today);
      expect(result.isEmpty, isTrue);
      expect(await periods(), isEmpty);
    });

    test('a non-anchor rule alone still produces no periods', () async {
      await repos.incomeRules.create(
        spaceId: space.id,
        title: 'Rent from tenants',
        scheduleType: ScheduleType.fixedDate,
        fixedDay: 5,
        amount: m('400'),
      );
      await service.refresh(space, today);
      expect(await periods(), isEmpty);
    });
  });

  group('materialisation', () {
    test('one anchor produces the six-period horizon', () async {
      await anchorOn(26);
      await service.refresh(space, today);

      final List<BudgetPeriod> rows = await periods();
      expect(rows, hasLength(6));
      expect(rows.first.startDate, d('2026-02-26'));
      expect(rows.first.endDate, d('2026-03-25'));
    });

    test('boundaries abut without gaps or overlaps', () async {
      await anchorOn(15);
      await service.refresh(space, today);

      final List<BudgetPeriod> rows = await periods();
      for (int i = 0; i < rows.length - 1; i++) {
        expect(rows[i].endDate!.addDays(1), rows[i + 1].startDate);
      }
    });

    test('two anchors split the month between them', () async {
      await anchorOn(10, title: 'Mine');
      await anchorOn(25, title: 'Partner');
      await service.refresh(space, today);

      final List<String> anchors = (await periods())
          .take(3)
          .map((BudgetPeriod p) => p.anchorDate!.toIso())
          .toList();
      expect(anchors, <String>['2026-03-10', '2026-03-25', '2026-04-10']);
    });

    test('coincident anchors merge into one period', () async {
      await anchorOn(15, title: 'Mine');
      await anchorOn(15, title: 'Partner');
      await service.refresh(space, today);

      final List<BudgetPeriod> rows = await periods();
      for (final BudgetPeriod p in rows) {
        expect(p.startDate.daysUntil(p.endDate!) + 1, greaterThanOrEqualTo(1));
      }
      expect(
        rows.map((BudgetPeriod p) => p.anchorDate!.toIso()).toSet(),
        hasLength(rows.length),
      );
    });

    test('a second refresh is idempotent', () async {
      await anchorOn(26);
      await service.refresh(space, today);
      final List<String> firstIds = (await periods())
          .map((BudgetPeriod p) => p.id)
          .toList();

      await service.refresh(space, today);
      final List<String> secondIds = (await periods())
          .map((BudgetPeriod p) => p.id)
          .toList();

      expect(secondIds, firstIds);
    });
  });

  group('future incomes', () {
    test(
      'each rule materialises its occurrences up to the last boundary',
      () async {
        // Occurrences stop at the last period.
        await anchorOn(26);
        await service.refresh(space, today);

        final List<Income> rows = await repos.incomes.inSpace(space.id);
        final CalendarDate lastBoundary = (await periods()).last.endDate!;
        expect(rows, isNotEmpty);
        // The rule was created today.
        expect(rows.first.expectedDate, d('2026-03-26'));
        expect(
          rows.every((Income i) => !i.expectedDate.isAfter(lastBoundary)),
          isTrue,
        );
        expect(rows.every((Income i) => i.amount == m('3000')), isTrue);
      },
    );

    test('history before the current cycle is not invented', () async {
      // The 1 March occurrence opens the current cycle; earlier ones are not
      // written.
      await anchorOn(1);
      await service.refresh(space, today);

      final List<Income> rows = await repos.incomes.inSpace(space.id);
      expect(
        rows.every((Income i) => !i.expectedDate.isBefore(d('2026-03-01'))),
        isTrue,
      );
    });

    test('a rule written today invents nothing behind it', () async {
      // Rule created on the 10th; the cycle opened on the 2nd, before the rule.
      await anchorOn(1);
      await service.refresh(space, today);

      final List<Income> rows = await repos.incomes.inSpace(space.id);
      expect(
        rows.every((Income i) => !i.expectedDate.isBefore(today)),
        isTrue,
        reason: 'materialised ${rows.map((Income i) => i.expectedDate)}',
      );
    });

    test('a rule that predates its cycle fills that cycle', () async {
      // A rule created before the cycle opened gets its anchor occurrence.
      final IncomeRuleRepository older = IncomeRuleRepository(
        db: db,
        clock: SpaceClock(
          timezone: 'UTC',
          now: () => DateTime.utc(2026, 1, 5, 12),
        ),
        userId: 'tester',
      );
      await older.create(
        spaceId: space.id,
        title: 'Salary',
        scheduleType: ScheduleType.fixedDate,
        fixedDay: 1,
        amount: m('3000'),
        isAnchor: true,
      );
      await service.refresh(space, today);

      final BudgetPeriod current = (await periods()).firstWhere(
        (BudgetPeriod p) =>
            !p.startDate.isAfter(today) &&
            (p.endDate == null || !p.endDate!.isBefore(today)),
      );
      final List<Income> rows = await repos.incomes.inSpace(space.id);
      expect(
        rows.any((Income i) => i.expectedDate == current.anchorDate),
        isTrue,
        reason:
            'the cycle opened on ${current.anchorDate} with no income row '
            'to say what arrived',
      );
    });

    test('a second refresh adds nothing', () async {
      await anchorOn(26);
      await service.refresh(space, today);
      final int first = (await repos.incomes.inSpace(space.id)).length;

      final PeriodRefresh again = await service.refresh(space, today);
      expect(again.incomesMaterialised, 0);
      expect(await repos.incomes.inSpace(space.id), hasLength(first));
    });

    test('a deleted occurrence stays deleted', () async {
      // Deleted rows count as materialised.
      await anchorOn(26);
      await service.refresh(space, today);
      final List<Income> rows = await repos.incomes.inSpace(space.id);
      final Income dropped = rows.last;

      await repos.incomes.softDelete(dropped.id);
      await service.refresh(space, today);

      final List<Income> after = await repos.incomes.inSpace(space.id);
      expect(
        after.any((Income i) => i.expectedDate == dropped.expectedDate),
        isFalse,
      );
      expect(after, hasLength(rows.length - 1));
    });

    test('an occurrence edited by hand survives a refresh', () async {
      await anchorOn(26);
      await service.refresh(space, today);

      final Income first = (await repos.incomes.inSpace(space.id)).first;
      await repos.incomes.update(first.id, amount: Value<Decimal?>(m('3500')));

      await service.refresh(space, today);
      final Income after = (await repos.incomes.inSpace(space.id))
          .firstWhere((Income i) => i.id == first.id);
      expect(after.amount, m('3500'));
    });

    test('a floating salary materialises with no amount', () async {
      // Unknown, not zero.
      await anchorOn(26, amount: null);
      await service.refresh(space, today);

      final List<Income> rows = await repos.incomes.inSpace(space.id);
      expect(rows, isNotEmpty);
      expect(rows.every((Income i) => i.amount == null), isTrue);
    });

    test('non-anchor rules materialise too', () async {
      await anchorOn(26);
      await repos.incomeRules.create(
        spaceId: space.id,
        title: 'Rent from tenants',
        scheduleType: ScheduleType.fixedDate,
        fixedDay: 15,
        amount: m('400'),
      );
      await service.refresh(space, today);

      final List<Income> rows = await repos.incomes.inSpace(space.id);
      expect(
        rows.where((Income i) => i.title == 'Rent from tenants'),
        isNotEmpty,
      );
    });
  });

  group('regenerate', () {
    Future<List<Income>> live() async =>
        (await repos.incomes.inSpace(space.id)).toList()..sort(
          (Income a, Income b) => a.expectedDate.compareTo(b.expectedDate),
        );

    test('lays deleted, edited and moved occurrences out again', () async {
      final IncomeRecurrenceRule rule = await anchorOn(26);
      await service.refresh(space, today);
      final List<Income> before = await live();
      expect(before.length, greaterThanOrEqualTo(4));

      await repos.incomes.softDelete(before[0].id);
      await repos.incomes.update(
        before[1].id,
        amount: Value<Decimal?>(m('3500')),
      );
      await repos.incomes.update(
        before[2].id,
        expectedDate: Value<CalendarDate>(before[2].expectedDate.addDays(1)),
      );
      await repos.incomes.update(
        before[3].id,
        amount: Value<Decimal?>(m('2900')),
        isPaid: const Value<bool>(true),
      );

      final int changed = await service.regenerate(space, rule.id, today);
      expect(changed, greaterThanOrEqualTo(3));

      final List<Income> after = await live();
      expect(
        after.map((Income i) => i.expectedDate).toList(),
        before.map((Income i) => i.expectedDate).toList(),
      );
      expect(after[1].amount, m('3000'));
      expect(after[3].isPaid, isTrue);
      expect(after[3].amount, m('2900'));

      expect(await service.regenerate(space, rule.id, today), 0);
    });

    test('a schedule edited back and forth leaves no gaps', () async {
      final IncomeRecurrenceRule rule = await anchorOn(26);
      await service.refresh(space, today);
      final List<CalendarDate> original = <CalendarDate>[
        for (final Income i in await live()) i.expectedDate,
      ];

      Future<void> moveTo(int day) async {
        await repos.incomeRules.updateRule(
          rule.id,
          title: 'Salary',
          scheduleType: ScheduleType.fixedDate,
          amount: m('3000'),
          fixedDay: day,
        );
        await service.regenerate(space, rule.id, today);
      }

      await moveTo(20);
      await moveTo(26);
      expect(<CalendarDate>[
        for (final Income i in await live()) i.expectedDate,
      ], original);
    });
  });

  group('closed periods are history', () {
    test('a period whose end has passed is never rewritten', () async {
      await anchorOn(26);
      await service.refresh(space, today);
      final BudgetPeriod closed = (await periods()).first;

      final CalendarDate later = d('2026-05-10');
      await service.refresh(space, later);

      final BudgetPeriod after = (await repos.periods.inSpace(space.id))
          .firstWhere((BudgetPeriod p) => p.id == closed.id);
      expect(after.startDate, closed.startDate);
      expect(after.endDate, closed.endDate);
    });

    test('open periods move in place, keeping their id', () async {
      await anchorOn(26);
      await service.refresh(space, today);
      final BudgetPeriod current = (await periods()).first;

      await repos.incomeRules.softDelete(
        (await repos.incomeRules.inSpace(space.id)).first.id,
      );
      await anchorOn(20);
      await service.refresh(space, today);

      final BudgetPeriod after = (await periods()).first;
      expect(after.id, current.id, reason: 'the row moved, not replaced');
      expect(after.anchorDate, isNot(current.anchorDate));
    });
  });

  group('binding records to periods', () {
    test('an auto payment binds to the period holding its date', () async {
      await anchorOn(26);
      final Payment payment = await repos.payments.create(
        spaceId: space.id,
        title: 'Rent',
        amount: m('600'),
        dueDate: d('2026-03-15'),
        expenseType: ExpenseType.mandatory,
      );
      await service.refresh(space, today);

      final Payment after = (await repos.payments.byId(payment.id))!;
      final BudgetPeriod containing = (await periods()).firstWhere(
        (BudgetPeriod p) => p.startDate == d('2026-02-26'),
      );
      expect(after.budgetPeriodId, containing.id);
    });

    test(
      'a payment due on the next anchor belongs to the next period',
      () async {
        // A payment on the anchor date belongs to the new cycle.
        await anchorOn(26);
        final Payment payment = await repos.payments.create(
          spaceId: space.id,
          title: 'Card',
          amount: m('100'),
          dueDate: d('2026-03-26'),
          expenseType: ExpenseType.mandatory,
        );
        await service.refresh(space, today);

        final Payment after = (await repos.payments.byId(payment.id))!;
        final BudgetPeriod next = (await periods()).firstWhere(
          (BudgetPeriod p) => p.startDate == d('2026-03-26'),
        );
        expect(after.budgetPeriodId, next.id);
      },
    );

    test('a manual pin survives a recompute', () async {
      await anchorOn(26);
      await service.refresh(space, today);
      final BudgetPeriod chosen = (await periods()).last;

      final Payment payment = await repos.payments.create(
        spaceId: space.id,
        title: 'Deliberate',
        amount: m('100'),
        dueDate: d('2026-03-15'),
        expenseType: ExpenseType.variable,
      );
      await repos.payments.setPeriod(
        payment.id,
        chosen.id,
        assignment: PeriodAssignment.manual,
      );

      await service.refresh(space, today);
      final Payment after = (await repos.payments.byId(payment.id))!;
      expect(after.budgetPeriodId, chosen.id);
      expect(after.periodAssignment, PeriodAssignment.manual);
    });

    test('a pin to a vanished period falls back to auto', () async {
      await anchorOn(26);
      await service.refresh(space, today);
      final BudgetPeriod doomed = (await periods()).last;

      final Payment payment = await repos.payments.create(
        spaceId: space.id,
        title: 'Orphan',
        amount: m('100'),
        dueDate: d('2026-03-15'),
        expenseType: ExpenseType.variable,
      );
      await repos.payments.setPeriod(
        payment.id,
        doomed.id,
        assignment: PeriodAssignment.manual,
      );

      // The pinned period is gone, as after a merge.
      await repos.periods.softDelete(doomed.id);

      final PeriodRefresh result = await service.refresh(space, today);
      final Payment after = (await repos.payments.byId(payment.id))!;
      expect(after.periodAssignment, PeriodAssignment.auto);
      expect(after.budgetPeriodId, isNotNull);
      expect(result.reboundToAuto, 1);
    });

    test('incomes bind to their period as well', () async {
      await anchorOn(26);
      await service.refresh(space, today);

      final List<Income> rows = await repos.incomes.inSpace(space.id);
      expect(rows.every((Income i) => i.budgetPeriodId != null), isTrue);
    });
  });

  group('incomplete holiday data', () {
    // Flagged per period, by its anchor's year.
    PeriodService serviceMissing(Set<int> years) => PeriodService(
      repos: repos,
      calendar: WorkingDayCalendar.weekendsOnly(),
      missingHolidayYears: years,
    );

    test('a period anchored in a missing year is flagged', () async {
      await anchorOn(5);
      await serviceMissing(<int>{today.year, today.year + 1})
          .refresh(space, today);
      expect(
        (await periods()).every((BudgetPeriod p) => p.holidayDataIncomplete),
        isTrue,
      );
    });

    test('a period anchored in a known year is not', () async {
      await anchorOn(5);
      await service.refresh(space, today);
      expect(
        (await periods()).any((BudgetPeriod p) => p.holidayDataIncomplete),
        isFalse,
      );
    });

    test('the flag clears when the data arrives', () async {
      await anchorOn(5);
      await serviceMissing(<int>{today.year, today.year + 1})
          .refresh(space, today);
      // Same rows, flag cleared.
      await service.refresh(space, today);
      expect(
        (await periods()).any((BudgetPeriod p) => p.holidayDataIncomplete),
        isFalse,
      );
    });
  });

  group('a settled anchor moves the cycle it opens', () {
    Future<Income> anchorIncomeOf(BudgetPeriod period) async {
      final List<Income> rows = await repos.incomes.inSpace(space.id);
      return rows.firstWhere((Income i) => i.budgetPeriodId == period.id);
    }

    Future<BudgetPeriod> periodAt(int index) async => (await periods())[index];

    test('the cycle starts on the day the money arrived', () async {
      await anchorOn(15);
      await service.refresh(space, today);

      // The next cycle: it and its predecessor are both open.
      final BudgetPeriod second = await periodAt(1);
      final Income salary = await anchorIncomeOf(second);
      await repos.incomes.update(
        salary.id,
        isPaid: const Value<bool>(true),
        actualDate: Value<CalendarDate>(salary.expectedDate.addDays(-2)),
      );
      await service.refresh(space, today);

      final BudgetPeriod moved = await periodAt(1);
      expect(moved.startDate, salary.expectedDate.addDays(-2));
      expect(moved.anchorDate, salary.expectedDate.addDays(-2));
    });

    test('the previous cycle ends the day before', () async {
      await anchorOn(15);
      await service.refresh(space, today);

      final BudgetPeriod second = await periodAt(1);
      final Income salary = await anchorIncomeOf(second);
      final CalendarDate actual = salary.expectedDate.addDays(-2);
      await repos.incomes.update(
        salary.id,
        isPaid: const Value<bool>(true),
        actualDate: Value<CalendarDate>(actual),
      );
      await service.refresh(space, today);

      expect((await periodAt(0)).endDate, actual.addDays(-1));
    });

    test('later cycles keep the dates the schedule computed', () async {
      await anchorOn(15);
      await service.refresh(space, today);
      final CalendarDate thirdStart = (await periodAt(2)).startDate;

      final BudgetPeriod second = await periodAt(1);
      final Income salary = await anchorIncomeOf(second);
      await repos.incomes.update(
        salary.id,
        isPaid: const Value<bool>(true),
        actualDate: Value<CalendarDate>(salary.expectedDate.addDays(-2)),
      );
      await service.refresh(space, today);

      // Later periods keep their scheduled dates.
      expect((await periodAt(2)).startDate, thirdStart);
    });

    test('the window collapses onto the day it arrived', () async {
      await anchorOn(15);
      await service.refresh(space, today);

      final BudgetPeriod second = await periodAt(1);
      final Income salary = await anchorIncomeOf(second);
      final CalendarDate actual = salary.expectedDate.addDays(-2);
      await repos.incomes.update(
        salary.id,
        isPaid: const Value<bool>(true),
        actualDate: Value<CalendarDate>(actual),
      );
      await service.refresh(space, today);

      final BudgetPeriod moved = await periodAt(1);
      expect(moved.windowStart, actual);
      expect(moved.windowEnd, actual);
    });

    test('an unconfirmed receipt moves nothing', () async {
      await anchorOn(15);
      await service.refresh(space, today);
      final CalendarDate before = (await periodAt(1)).startDate;

      // Received without a date: nothing to move to.
      final Income salary = await anchorIncomeOf(await periodAt(1));
      await repos.incomes.update(salary.id, isPaid: const Value<bool>(true));
      await service.refresh(space, today);

      expect((await periodAt(1)).startDate, before);
    });
  });

  test('Flow spaces are left alone entirely', () async {
    final Space flow = await repos.spaces.create(
      title: 'Freelance',
      spaceType: SpaceType.personal,
      budgetMode: BudgetMode.flow,
      ownerId: 'tester',
      timezone: 'UTC',
      currencyCode: 'EUR',
    );
    final PeriodRefresh result = await service.refresh(flow, today);
    expect(result.isEmpty, isTrue);
    expect(await repos.periods.incomeDrivenIn(flow.id), isEmpty);
  });
}
