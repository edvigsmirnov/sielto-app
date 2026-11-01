import 'package:decimal/decimal.dart';
import 'package:meta/meta.dart';
import 'package:sielto/domain/ledger/ledger_entry.dart';
import 'package:sielto/domain/value/calendar_date.dart';

/// End-of-day balances for the next few days.
@immutable
class DailyProjection {
  const DailyProjection({
    required this.days,
    required this.balances,
    required this.spend,
  });

  /// Day-by-day walk from [from]; entries land on their own dates, earlier
  /// ones in the opening balance.
  factory DailyProjection.walk({
    required Decimal available,
    required List<LedgerEntry> entries,
    required CalendarDate from,
  }) {
    final List<CalendarDate> days = <CalendarDate>[
      for (int i = 0; i < horizonDays; i++) from.addDays(i),
    ];
    final Map<CalendarDate, List<LedgerEntry>> byDay =
        <CalendarDate, List<LedgerEntry>>{};
    Decimal balance = available;
    for (final LedgerEntry e in entries) {
      if (e.date.isBefore(from)) {
        balance = _apply(balance, e);
      } else {
        (byDay[e.date] ??= <LedgerEntry>[]).add(e);
      }
    }

    Decimal spend = Decimal.zero;
    final List<Decimal> balances = <Decimal>[];
    for (final CalendarDate day in days) {
      for (final LedgerEntry e in byDay[day] ?? const <LedgerEntry>[]) {
        balance = _apply(balance, e);
        if (!e.isIncome) spend += e.amount;
      }
      balances.add(balance);
    }
    return DailyProjection(days: days, balances: balances, spend: spend);
  }

  static const int horizonDays = 10;

  static Decimal _apply(Decimal balance, LedgerEntry e) =>
      e.isIncome ? balance + e.amount : balance - e.amount;

  final List<CalendarDate> days;

  final List<Decimal> balances;

  /// Planned spend over the window.
  final Decimal spend;

  /// [spend] over the window's length. Zero when nothing is planned.
  Decimal get averageSpendPerDay => (spend / Decimal.fromInt(horizonDays))
      .toDecimal(scaleOnInfinitePrecision: 2);

  Decimal get lowest =>
      balances.reduce((Decimal a, Decimal b) => a < b ? a : b);

  Decimal get highest =>
      balances.reduce((Decimal a, Decimal b) => a > b ? a : b);
}
