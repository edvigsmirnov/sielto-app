import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/app/startup.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/income_repository.dart';
import 'package:sielto/core/time/space_clock.dart';
import 'package:sielto/domain/ledger/ledger_walker.dart';
import 'package:sielto/domain/schedule/working_days.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/periods/period_service.dart';
import 'package:sielto/features/space/period_ledger.dart';

CalendarDate d(String iso) => CalendarDate.parse(iso);
Decimal m(String v) => Decimal.parse(v);

/// One income cycle from the tables. Every listed record counts, and the
/// anchor counts once.
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

  Future<PeriodLedger> ledgerOf(BudgetPeriod period) async {
    final List<IncomeRecurrenceRule> rules = await repos.incomeRules.inSpace(
      space.id,
    );
    return buildPeriodLedger(
      period: period,
      payments: await repos.payments.inSpace(space.id),
      incomes: await repos.incomes.inSpace(space.id),
      anchorRuleIds: <String>{
        for (final IncomeRecurrenceRule r in rules)
          if (r.isAnchor) r.id,
      },
      today: today,
    );
  }

  Future<BudgetPeriod> currentPeriod() async {
    final List<BudgetPeriod> all = await repos.periods.incomeDrivenIn(space.id);
    return all.firstWhere(
      (BudgetPeriod p) =>
          !p.startDate.isAfter(today) &&
          (p.endDate == null || !p.endDate!.isBefore(today)),
    );
  }

  /// A salary rule created before the cycle under test opened.
  Future<void> addSalary({String? amount = '3224'}) async {
    await IncomeRuleRepository(
      db: db,
      clock: SpaceClock(
        timezone: 'UTC',
        now: () => DateTime.utc(2026, 1, 4, 12),
      ),
      userId: 'tester',
    ).create(
      spaceId: space.id,
      title: 'Salary',
      scheduleType: ScheduleType.fixedDate,
      fixedDay: 5,
      amount: amount == null ? null : m(amount),
      isAnchor: true,
    );
    await service.refresh(space, today);
  }

  test('the anchor is counted once, not once per materialised month', () async {
    await repos.payments.create(
      spaceId: space.id,
      title: 'Rent',
      amount: m('900'),
      dueDate: d('2026-03-12'),
      expenseType: ExpenseType.mandatory,
    );
    await addSalary();

    final PeriodLedger ledger = await ledgerOf(await currentPeriod());
    expect(ledger.anchorAmount, m('3224'));
  });

  test('a payment written before the recompute still counts', () async {
    await addSalary();
    // No period: binding happens on the next refresh.
    await repos.payments.create(
      spaceId: space.id,
      title: 'Rent',
      amount: m('900'),
      dueDate: d('2026-03-12'),
      expenseType: ExpenseType.mandatory,
    );

    final PeriodLedger ledger = await ledgerOf(await currentPeriod());
    expect(ledger.totalPlanned, m('900'));
    expect(ledger.freeCash, m('2324'));
  });

  group('no figure', () {
    test('a cycle with no income at all computes from zero', () async {
      await addSalary();
      // Every occurrence removed.
      for (final Income i in await repos.incomes.inSpace(space.id)) {
        await repos.incomes.softDelete(i.id);
      }

      final PeriodLedger ledger = await ledgerOf(await currentPeriod());
      expect(ledger.anchorAmount, Decimal.zero);
      expect(ledger.isComputable, isTrue);
      expect(ledger.freeCash, Decimal.zero);
    });

    test('an anchor with no amount stays uncomputable', () async {
      // Amount unknown.
      await addSalary(amount: null);

      final PeriodLedger ledger = await ledgerOf(await currentPeriod());
      expect(ledger.anchorAmount, isNull);
      expect(ledger.isComputable, isFalse);
    });

    test('an empty cycle still reports what it owes', () async {
      await addSalary();
      for (final Income i in await repos.incomes.inSpace(space.id)) {
        await repos.incomes.softDelete(i.id);
      }
      await repos.payments.create(
        spaceId: space.id,
        title: 'Rent',
        amount: m('900'),
        dueDate: d('2026-03-12'),
        expenseType: ExpenseType.mandatory,
      );

      final PeriodLedger ledger = await ledgerOf(await currentPeriod());
      expect(ledger.totalPlanned, m('900'));
      expect(ledger.freeCash, isNull);
    });
  });

  test('a payment dated outside the cycle does not count', () async {
    await addSalary();
    await repos.payments.create(
      spaceId: space.id,
      title: 'Next month',
      amount: m('900'),
      dueDate: d('2026-06-20'),
      expenseType: ExpenseType.mandatory,
    );

    final PeriodLedger ledger = await ledgerOf(await currentPeriod());
    expect(ledger.totalPlanned, Decimal.zero);
  });

  test('the figures follow the payment once it is bound', () async {
    await addSalary();
    await repos.payments.create(
      spaceId: space.id,
      title: 'Rent',
      amount: m('900'),
      dueDate: d('2026-03-12'),
      expenseType: ExpenseType.mandatory,
    );
    // Binding does not change the result.
    await service.refresh(space, today);

    final PeriodLedger ledger = await ledgerOf(await currentPeriod());
    expect(ledger.freeCash, m('2324'));
  });

  group('a cycle with no income of its own', () {
    /// Removes every income from the current cycle.
    Future<BudgetPeriod> emptyOfIncome() async {
      await addSalary();
      final BudgetPeriod period = await currentPeriod();
      for (final Income i in await repos.incomes.inSpace(space.id)) {
        await repos.incomes.softDelete(i.id);
      }
      return period;
    }

    test('with everything settled it is not judged at all', () async {
      final BudgetPeriod period = await emptyOfIncome();
      await repos.payments.create(
        spaceId: space.id,
        title: 'Rent',
        amount: m('900'),
        dueDate: d('2026-03-12'),
        expenseType: ExpenseType.mandatory,
        isPaid: true,
      );

      final PeriodLedger ledger = await ledgerOf(period);
      expect(ledger.hasIncome, isFalse);
      expect(ledger.isJudged, isFalse);
      expect(ledger.coverage, isNull);
      expect(ledger.baseCoverage, isNull);
      expect(ledger.moneyEndsAt, isNull);
      expect(ledger.lastCoveredDay, isNull);
      expect(ledger.coverageByEntry, isEmpty);
      expect(ledger.freeCash, m('-900'));
    });

    test('with nothing in it at all it is not judged either', () async {
      final PeriodLedger ledger = await ledgerOf(await emptyOfIncome());
      expect(ledger.isJudged, isFalse);
      expect(ledger.coverage, isNull);
      expect(ledger.freeCash, Decimal.zero);
    });

    test('something still owed brings the verdict back', () async {
      final BudgetPeriod period = await emptyOfIncome();
      await repos.payments.create(
        spaceId: space.id,
        title: 'Rent',
        amount: m('900'),
        dueDate: d('2026-03-12'),
        expenseType: ExpenseType.mandatory,
      );

      final PeriodLedger ledger = await ledgerOf(period);
      expect(ledger.isJudged, isTrue);
      expect(ledger.coverage, Coverage.short);
      expect(ledger.moneyEndsAt, isNotNull);
    });
  });
}
