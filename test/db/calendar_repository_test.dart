import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/app/startup.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/calendar_repository.dart';
import 'package:sielto/core/db/repositories/income_repository.dart';
import 'package:sielto/core/db/repositories/payment_repository.dart';
import 'package:sielto/core/db/repositories/space_repository.dart';
import 'package:sielto/core/time/space_clock.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';

/// The Calendar's aggregate query (spec 8.1).
///
/// The whole screen rests on it, and every failure mode is silent: a day that
/// merges the wrong rows still draws a plausible number.
void main() {
  late AppDatabase db;
  late SpaceRepository spaces;
  late PaymentRepository payments;
  late IncomeRepository incomes;
  late CalendarRepository calendar;
  late Space space;

  setUpAll(SpaceClock.initialize);

  setUp(() async {
    db = inMemoryDatabase();
    final SpaceClock clock = SpaceClock(
      timezone: 'Europe/Berlin',
      now: () => DateTime.utc(2026, 8, 14, 12),
    );
    spaces = SpaceRepository(db: db, clock: clock);
    payments = PaymentRepository(db: db, clock: clock, userId: 'user-1');
    incomes = IncomeRepository(db: db, clock: clock, userId: 'user-1');
    calendar = CalendarRepository(db: db);

    space = await spaces.create(
      title: 'Household',
      spaceType: SpaceType.family,
      budgetMode: BudgetMode.flow,
      ownerId: 'user-1',
      timezone: 'Europe/Berlin',
      currencyCode: 'EUR',
    );
  });

  tearDown(() => db.close());

  Future<void> spend(
    String title,
    String amount,
    CalendarDate on, {
    bool isPaid = false,
  }) => payments.create(
    spaceId: space.id,
    title: title,
    amount: Decimal.parse(amount),
    dueDate: on,
    expenseType: ExpenseType.variable,
    isPaid: isPaid,
  );

  Future<void> earn(String title, String? amount, CalendarDate on) =>
      incomes.create(
        spaceId: space.id,
        title: title,
        expectedDate: on,
        amount: amount == null ? null : Decimal.parse(amount),
      );

  Future<Map<CalendarDate, DayTotals>> totals(
    CalendarDate from,
    CalendarDate to,
  ) => calendar.dailyTotals(space.id, from, to);

  test('a day with nothing on it is absent, not zero', () async {
    await spend('Groceries', '22.50', const CalendarDate(2026, 8, 12));

    final Map<CalendarDate, DayTotals> byDay = await totals(
      const CalendarDate(2026, 8, 10),
      const CalendarDate(2026, 8, 16),
    );
    expect(byDay.keys, <CalendarDate>[const CalendarDate(2026, 8, 12)]);
  });

  test('expenses and incomes stay apart on the same day', () async {
    const CalendarDate day = CalendarDate(2026, 8, 12);
    await spend('Groceries', '22.50', day);
    await spend('Pharmacy', '10', day);
    await earn('Salary', '3224', day);

    final DayTotals sums = (await totals(day, day))[day]!;
    expect(sums.expenses, Decimal.parse('32.50'));
    expect(sums.income, Decimal.parse('3224'));
    expect(sums.net, Decimal.parse('3191.50'));
    expect(sums.recordCount, 3);
  });

  test('money is summed exactly, not through a float', () async {
    // The reason the fold happens in Dart: SUM() over a TEXT column goes
    // through REAL, and three tenths of a cent is where that shows.
    const CalendarDate day = CalendarDate(2026, 8, 12);
    for (int i = 0; i < 3; i++) {
      await spend('Coffee $i', '0.10', day);
    }
    expect((await totals(day, day))[day]!.expenses, Decimal.parse('0.30'));
  });

  test('a floating income counts as a record with no figure', () async {
    // An income whose amount is not known yet still puts something on the day
    // (spec 4.7), and the cell has to be able to say so.
    const CalendarDate day = CalendarDate(2026, 8, 27);
    await earn('Salary', null, day);

    final DayTotals sums = (await totals(day, day))[day]!;
    expect(sums.recordCount, 1);
    expect(sums.income, Decimal.zero);
    expect(sums.hasUnknownAmount, isTrue);
    expect(sums.isEmpty, isFalse);
  });

  test('paid records are counted as settled', () async {
    const CalendarDate day = CalendarDate(2026, 8, 12);
    await spend('Rent', '900', day, isPaid: true);
    await spend('Pharmacy', '10', day);

    final DayTotals sums = (await totals(day, day))[day]!;
    expect(sums.paidCount, 1);
    expect(sums.recordCount, 2);
  });

  test('the range is inclusive at both ends', () async {
    await spend('First', '1', const CalendarDate(2026, 8, 10));
    await spend('Last', '2', const CalendarDate(2026, 8, 16));
    await spend('Outside', '4', const CalendarDate(2026, 8, 17));

    final Map<CalendarDate, DayTotals> byDay = await totals(
      const CalendarDate(2026, 8, 10),
      const CalendarDate(2026, 8, 16),
    );
    expect(byDay.length, 2);
    expect(byDay[const CalendarDate(2026, 8, 17)], isNull);
  });

  test('a deleted record leaves the calendar', () async {
    const CalendarDate day = CalendarDate(2026, 8, 12);
    await spend('Groceries', '22.50', day);
    final List<Payment> rows = await payments.onDay(space.id, day);
    await payments.softDelete(rows.single.id);

    expect(await totals(day, day), isEmpty);
  });

  test('another Space contributes nothing', () async {
    final Space other = await spaces.create(
      title: 'Trip',
      spaceType: SpaceType.trip,
      budgetMode: BudgetMode.flow,
      ownerId: 'user-1',
      timezone: 'Europe/Berlin',
      currencyCode: 'EUR',
    );
    const CalendarDate day = CalendarDate(2026, 8, 12);
    await payments.create(
      spaceId: other.id,
      title: 'Hotel',
      amount: Decimal.parse('400'),
      dueDate: day,
      expenseType: ExpenseType.variable,
    );

    expect(await totals(day, day), isEmpty);
  });

  test('the Year view groups by month, keyed on the first', () async {
    await spend('January', '100', const CalendarDate(2026, 1, 5));
    await spend('January again', '50', const CalendarDate(2026, 1, 31));
    await earn('March salary', '3000', const CalendarDate(2026, 3, 27));
    await spend('Next year', '999', const CalendarDate(2027, 1, 5));

    final Map<CalendarDate, DayTotals> byMonth = await calendar
        .watchMonthlyTotals(space.id, 2026)
        .first;

    expect(byMonth.keys.toSet(), <CalendarDate>{
      const CalendarDate(2026, 1, 1),
      const CalendarDate(2026, 3, 1),
    });
    expect(
      byMonth[const CalendarDate(2026, 1, 1)]!.expenses,
      Decimal.parse('150'),
    );
    expect(
      byMonth[const CalendarDate(2026, 3, 1)]!.income,
      Decimal.parse('3000'),
    );
  });

  test('the stream re-emits when a record is added', () async {
    const CalendarDate day = CalendarDate(2026, 8, 12);
    final Stream<Map<CalendarDate, DayTotals>> stream = calendar
        .watchDailyTotals(space.id, day, day);

    expect(await stream.first, isEmpty);
    await spend('Groceries', '22.50', day);
    expect((await stream.first)[day]!.expenses, Decimal.parse('22.50'));
  });
}
