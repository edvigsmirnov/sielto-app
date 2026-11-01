import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/domain/ledger/daily_projection.dart';
import 'package:sielto/domain/ledger/ledger_entry.dart';
import 'package:sielto/domain/value/calendar_date.dart';

CalendarDate d(String iso) => CalendarDate.parse(iso);
Decimal m(String v) => Decimal.parse(v);

LedgerEntry entry(String date, String amount, {bool income = false}) =>
    LedgerEntry(
      id: '$date$amount',
      date: d(date),
      amount: m(amount),
      isIncome: income,
    );

void main() {
  test('overdue entries open the window; later ones land on their day', () {
    final DailyProjection p = DailyProjection.walk(
      available: m('100'),
      entries: <LedgerEntry>[
        entry('2026-03-08', '10'),
        entry('2026-03-10', '20'),
        entry('2026-03-12', '50', income: true),
        entry('2026-03-19', '15'),
        entry('2026-03-20', '1000'),
      ],
      from: d('2026-03-10'),
    );

    expect(p.days.first, d('2026-03-10'));
    expect(p.days.last, d('2026-03-19'));
    expect(p.balances.first, m('70'));
    expect(p.balances[2], m('120'));
    expect(p.balances.last, m('105'));
    expect(p.spend, m('35'));
    expect(p.averageSpendPerDay, m('3.5'));
    expect(p.lowest, m('70'));
    expect(p.highest, m('120'));
  });
}
