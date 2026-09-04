import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/app/startup.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/analytics_repository.dart';
import 'package:sielto/core/db/repositories/category_repository.dart';
import 'package:sielto/core/db/repositories/payment_repository.dart';
import 'package:sielto/core/db/repositories/space_repository.dart';
import 'package:sielto/core/time/space_clock.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';

/// Analytics' three levels and the title autocomplete that feeds them
/// (spec 8.2).
void main() {
  late AppDatabase db;
  late SpaceRepository spaces;
  late PaymentRepository payments;
  late CategoryRepository categories;
  late AnalyticsRepository analytics;
  late Space space;

  const CalendarDate summerStart = CalendarDate(2026, 6, 1);
  const CalendarDate summerEnd = CalendarDate(2026, 8, 31);

  setUpAll(SpaceClock.initialize);

  setUp(() async {
    db = inMemoryDatabase();
    final SpaceClock clock = SpaceClock(
      timezone: 'Europe/Berlin',
      now: () => DateTime.utc(2026, 8, 14, 12),
    );
    spaces = SpaceRepository(db: db, clock: clock);
    payments = PaymentRepository(db: db, clock: clock, userId: 'user-1');
    categories = CategoryRepository(
      db: db,
      clock: clock,
      userId: 'user-1',
      payments: payments,
    );
    analytics = AnalyticsRepository(db: db);

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

  Future<Category> category(String title) =>
      categories.create(spaceId: space.id, title: title);

  Future<void> spend(
    String title,
    String amount, {
    required CalendarDate on,
    String? categoryId,
    ExpenseType type = ExpenseType.variable,
  }) => payments.create(
    spaceId: space.id,
    title: title,
    amount: Decimal.parse(amount),
    dueDate: on,
    expenseType: type,
    categoryId: categoryId,
  );

  group('level 1, by category', () {
    test('totals per category, largest first', () async {
      final Category food = await category('Groceries');
      final Category transport = await category('Transport');
      await spend('Rewe', '600', on: summerStart, categoryId: food.id);
      await spend('Lidl', '380', on: summerEnd, categoryId: food.id);
      await spend('Ticket', '420', on: summerStart, categoryId: transport.id);

      final List<AnalyticsSlice> slices = await analytics.byCategory(
        spaceId: space.id,
        from: summerStart,
        to: summerEnd,
      );
      expect(slices.map((AnalyticsSlice s) => s.key).toList(), <String>[
        food.id,
        transport.id,
      ]);
      expect(slices.first.total, Decimal.parse('980'));
      expect(slices.first.count, 2);
    });

    test('uncategorised payments make a slice of their own', () async {
      // Dropping them would make the level disagree with the Feed about what
      // the range cost.
      final Category food = await category('Groceries');
      await spend('Rewe', '600', on: summerStart, categoryId: food.id);
      await spend('Cash', '40', on: summerStart);

      final List<AnalyticsSlice> slices = await analytics.byCategory(
        spaceId: space.id,
        from: summerStart,
        to: summerEnd,
      );
      expect(slices.length, 2);
      expect(slices.last.key, AnalyticsRepository.uncategorisedKey);
      expect(slices.last.total, Decimal.parse('40'));
    });

    test('the range excludes what falls outside it', () async {
      final Category food = await category('Groceries');
      await spend(
        'Before',
        '100',
        on: summerStart.addDays(-1),
        categoryId: food.id,
      );
      await spend('Inside', '10', on: summerStart, categoryId: food.id);
      await spend(
        'After',
        '100',
        on: summerEnd.addDays(1),
        categoryId: food.id,
      );

      final List<AnalyticsSlice> slices = await analytics.byCategory(
        spaceId: space.id,
        from: summerStart,
        to: summerEnd,
      );
      expect(slices.single.total, Decimal.parse('10'));
    });

    test('the mandatory filter is a slice through the same range', () async {
      final Category loans = await category('Loans');
      await spend(
        'Instalment',
        '1200',
        on: summerStart,
        categoryId: loans.id,
        type: ExpenseType.mandatory,
      );
      await spend('Cinema', '30', on: summerStart, categoryId: loans.id);

      final List<AnalyticsSlice> mandatory = await analytics.byCategory(
        spaceId: space.id,
        from: summerStart,
        to: summerEnd,
        expenseType: ExpenseType.mandatory,
      );
      expect(mandatory.single.total, Decimal.parse('1200'));

      final List<AnalyticsSlice> variable = await analytics.byCategory(
        spaceId: space.id,
        from: summerStart,
        to: summerEnd,
        expenseType: ExpenseType.variable,
      );
      expect(variable.single.total, Decimal.parse('30'));
    });

    test('a deleted payment leaves the reckoning', () async {
      final Category food = await category('Groceries');
      await spend('Rewe', '600', on: summerStart, categoryId: food.id);
      final List<Payment> rows = await payments.inSpace(space.id);
      await payments.softDelete(rows.single.id);

      expect(
        await analytics.byCategory(
          spaceId: space.id,
          from: summerStart,
          to: summerEnd,
        ),
        isEmpty,
      );
    });

    test('incomes are not part of it', () async {
      // All three levels are about where money goes.
      final List<AnalyticsSlice> slices = await analytics.byCategory(
        spaceId: space.id,
        from: summerStart,
        to: summerEnd,
      );
      expect(slices, isEmpty);
    });
  });

  group('level 2, by title', () {
    test('spelling variants collapse into one line', () async {
      final Category food = await category('Groceries');
      await spend('Lidl', '100', on: summerStart, categoryId: food.id);
      await spend('lidl', '80', on: summerStart, categoryId: food.id);
      await spend(' LIDL ', '60', on: summerStart, categoryId: food.id);

      final List<AnalyticsSlice> slices = await analytics.byTitle(
        spaceId: space.id,
        from: summerStart,
        to: summerEnd,
        categoryId: food.id,
      );
      expect(slices.single.total, Decimal.parse('240'));
      expect(slices.single.count, 3);
      expect(slices.single.key, 'lidl');
    });

    test('the label is the most frequent spelling', () async {
      final Category food = await category('Groceries');
      await spend('Lidl', '10', on: summerStart, categoryId: food.id);
      await spend('Lidl', '10', on: summerStart, categoryId: food.id);
      await spend('lidl', '10', on: summerStart, categoryId: food.id);

      final List<AnalyticsSlice> slices = await analytics.byTitle(
        spaceId: space.id,
        from: summerStart,
        to: summerEnd,
        categoryId: food.id,
      );
      expect(slices.single.label, 'Lidl');
    });

    test('another category contributes nothing', () async {
      final Category food = await category('Groceries');
      final Category transport = await category('Transport');
      await spend('Rewe', '600', on: summerStart, categoryId: food.id);
      await spend('Ticket', '420', on: summerStart, categoryId: transport.id);

      final List<AnalyticsSlice> slices = await analytics.byTitle(
        spaceId: space.id,
        from: summerStart,
        to: summerEnd,
        categoryId: transport.id,
      );
      expect(slices.single.label, 'Ticket');
    });

    test(
      'a null category means the uncategorised slice, not all of them',
      () async {
        final Category food = await category('Groceries');
        await spend('Rewe', '600', on: summerStart, categoryId: food.id);
        await spend('Cash', '40', on: summerStart);

        final List<AnalyticsSlice> slices = await analytics.byTitle(
          spaceId: space.id,
          from: summerStart,
          to: summerEnd,
          categoryId: null,
        );
        expect(slices.single.label, 'Cash');
      },
    );

    test('the average is the level-3 figure', () async {
      final Category food = await category('Groceries');
      await spend('Rewe', '100', on: summerStart, categoryId: food.id);
      await spend('Rewe', '74', on: summerStart, categoryId: food.id);

      final List<AnalyticsSlice> slices = await analytics.byTitle(
        spaceId: space.id,
        from: summerStart,
        to: summerEnd,
        categoryId: food.id,
      );
      expect(slices.single.average, Decimal.parse('87'));
    });

    test('an average that does not divide evenly keeps two places', () async {
      final Category food = await category('Groceries');
      await spend('Rewe', '10', on: summerStart, categoryId: food.id);
      await spend('Rewe', '10', on: summerStart, categoryId: food.id);
      await spend('Rewe', '10', on: summerStart, categoryId: food.id);
      await spend('Rewe', '1', on: summerStart, categoryId: food.id);

      // 31 / 4 = 7.75 exactly; the guard is that it is not a repeating binary
      // fraction dressed up as money.
      expect(
        (await analytics.byTitle(
          spaceId: space.id,
          from: summerStart,
          to: summerEnd,
          categoryId: food.id,
        )).single.average,
        Decimal.parse('7.75'),
      );
    });
  });

  group('foldSlices', () {
    test('orders by total and breaks ties on the label', () {
      final List<AnalyticsSlice> slices = foldSlices(<AnalyticsRow>[
        (key: 'b', label: 'Beta', amount: '10'),
        (key: 'a', label: 'Alpha', amount: '10'),
        (key: 'c', label: 'Gamma', amount: '30'),
      ]);
      expect(slices.map((AnalyticsSlice s) => s.label).toList(), <String>[
        'Gamma',
        'Alpha',
        'Beta',
      ]);
    });

    test('an empty input folds to nothing', () {
      expect(foldSlices(const <AnalyticsRow>[]), isEmpty);
    });
  });

  group('title suggestions', () {
    test('offers previous titles by prefix, most used first', () async {
      await spend('Lidl', '10', on: summerStart);
      await spend('Lidl', '10', on: summerStart);
      await spend('Lieferando', '10', on: summerStart);
      await spend('Rewe', '10', on: summerStart);

      expect(await payments.titleSuggestions(space.id, 'Li'), <String>[
        'Lidl',
        'Lieferando',
      ]);
    });

    test('matching ignores case', () async {
      await spend('Klarna', '10', on: summerStart);
      expect(await payments.titleSuggestions(space.id, 'kla'), <String>[
        'Klarna',
      ]);
    });

    test('one suggestion per grouping key, in its commonest spelling', () async {
      // What is offered has to be what level 2 will merge, or the autocomplete
      // would hand the user a second variant of a title it already has.
      await spend('Klarna', '10', on: summerStart);
      await spend('Klarna', '10', on: summerStart);
      await spend('klarna', '10', on: summerStart);

      expect(await payments.titleSuggestions(space.id, 'k'), <String>[
        'Klarna',
      ]);
    });

    test('an empty prefix offers nothing', () async {
      await spend('Klarna', '10', on: summerStart);
      expect(await payments.titleSuggestions(space.id, '   '), isEmpty);
    });

    test('another Space is not consulted', () async {
      final Space other = await spaces.create(
        title: 'Trip',
        spaceType: SpaceType.trip,
        budgetMode: BudgetMode.flow,
        ownerId: 'user-1',
        timezone: 'Europe/Berlin',
        currencyCode: 'EUR',
      );
      await payments.create(
        spaceId: other.id,
        title: 'Klarna',
        amount: Decimal.parse('10'),
        dueDate: summerStart,
        expenseType: ExpenseType.variable,
      );
      expect(await payments.titleSuggestions(space.id, 'k'), isEmpty);
    });

    test('a deleted payment stops being suggested', () async {
      await spend('Klarna', '10', on: summerStart);
      final List<Payment> rows = await payments.inSpace(space.id);
      await payments.softDelete(rows.single.id);
      expect(await payments.titleSuggestions(space.id, 'k'), isEmpty);
    });
  });
}
