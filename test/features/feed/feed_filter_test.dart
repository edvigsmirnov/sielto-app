import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/feed/feed_filter.dart';
import 'package:sielto/features/feed/feed_model.dart';

void main() {
  FeedRecord record({
    String title = 'Lidl',
    bool isIncome = false,
    bool isPaid = false,
    ExpenseType? type = ExpenseType.variable,
    String? categoryId = 'food',
    String? notes,
  }) => FeedRecord(
    id: title,
    date: const CalendarDate(2026, 3, 1),
    title: title,
    amount: Decimal.fromInt(10),
    isIncome: isIncome,
    isPaid: isPaid,
    sortOrder: 0,
    expenseType: isIncome ? null : type,
    categoryId: isIncome ? null : categoryId,
    notes: notes,
  );

  test('no filter is inactive', () {
    expect(FeedFilter.none.isActive, isFalse);
    expect(const FeedFilter(query: '  ').isActive, isFalse);
  });

  test('the query reads the title and the note, ignoring case', () {
    const FeedFilter f = FeedFilter(query: 'LID');
    expect(f.matches(record()), isTrue);
    expect(f.matches(record(title: 'Rewe', notes: 'next to lidl')), isTrue);
    expect(f.matches(record(title: 'Rewe')), isFalse);
  });

  test('conditions combine', () {
    const FeedFilter f = FeedFilter(
      kind: FeedKind.variable,
      status: FeedStatus.pending,
      categoryIds: <String>{'food'},
    );
    expect(f.matches(record()), isTrue);
    expect(f.matches(record(isPaid: true)), isFalse);
    expect(f.matches(record(type: ExpenseType.mandatory)), isFalse);
    expect(f.matches(record(categoryId: 'home')), isFalse);
    expect(f.matches(record(isIncome: true)), isFalse);
  });

  test('income kind keeps incomes only', () {
    const FeedFilter f = FeedFilter(kind: FeedKind.income);
    expect(f.matches(record(isIncome: true)), isTrue);
    expect(f.matches(record()), isFalse);
  });
}
