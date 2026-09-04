import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:meta/meta.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/domain/value/calendar_date.dart';

/// What one calendar cell knows: the sums, and how many records made them.
///
/// Expenses and incomes are held apart and both positive. The calendar draws
/// them on separate lines in opposite colours, so a single net figure would
/// have to be split again to be shown.
@immutable
class DayTotals {
  const DayTotals({
    required this.expenses,
    required this.income,
    required this.recordCount,
    required this.paidCount,
    required this.hasUnknownAmount,
  });

  /// Not a `const`: [Decimal.zero] is a final field, not a constant.
  static final DayTotals empty = DayTotals(
    expenses: Decimal.zero,
    income: Decimal.zero,
    recordCount: 0,
    paidCount: 0,
    hasUnknownAmount: false,
  );

  final Decimal expenses;
  final Decimal income;
  final int recordCount;

  /// Paid expenses and received incomes together. The Day view splits them
  /// again; a cell only needs to know whether the day is settled.
  final int paidCount;

  /// A floating income sits on the day with no figure yet (spec 4.7), so the
  /// income line is a lower bound rather than the total.
  final bool hasUnknownAmount;

  bool get isEmpty => recordCount == 0;

  Decimal get net => income - expenses;

  DayTotals add(
    Decimal amount, {
    required bool isIncome,
    required bool isPaid,
    required bool amountKnown,
  }) => DayTotals(
    expenses: isIncome ? expenses : expenses + amount,
    income: isIncome ? income + amount : income,
    recordCount: recordCount + 1,
    paidCount: isPaid ? paidCount + 1 : paidCount,
    hasUnknownAmount: hasUnknownAmount || !amountKnown,
  );
}

/// The Calendar's aggregate reads (spec 8.1).
///
/// Sums only. The Month, Week and Year views draw no titles, so they never
/// load a row: one grouping query answers a whole range, and the detail query
/// runs when a single day is opened.
///
/// Money is TEXT, so the sums are added up in Dart over [Decimal] — SQL's
/// `SUM` over that column would go through REAL. What SQL does here is the
/// grouping and the range filter, which is where the cost is.
class CalendarRepository {
  CalendarRepository({required this.db});

  final AppDatabase db;

  /// One row per day that has anything on it, between [from] and [to]
  /// inclusive. Days with no records are simply absent.
  Stream<Map<CalendarDate, DayTotals>> watchDailyTotals(
    String spaceId,
    CalendarDate from,
    CalendarDate to,
  ) => _combined(spaceId, from, to).watch().map(_foldByDay);

  Future<Map<CalendarDate, DayTotals>> dailyTotals(
    String spaceId,
    CalendarDate from,
    CalendarDate to,
  ) => _combined(spaceId, from, to).get().then(_foldByDay);

  /// The Year view: the same figures grouped by month (spec 8.1).
  ///
  /// Keyed by the first of each month, so a key is a [CalendarDate] like every
  /// other and the view does not carry a second kind of key.
  Stream<Map<CalendarDate, DayTotals>> watchMonthlyTotals(
    String spaceId,
    int year,
  ) => _combined(spaceId, CalendarDate(year, 1, 1), CalendarDate(year, 12, 31))
      .watch()
      .map(
        (List<QueryRow> rows) =>
            _fold(rows, (CalendarDate d) => d.firstOfMonth),
      );

  /// Payments and incomes over one range, as one date-and-amount stream.
  ///
  /// `UNION ALL` rather than two queries: the two tables answer the same
  /// question here and merging them in SQL keeps one pass and one sort.
  Selectable<QueryRow> _combined(
    String spaceId,
    CalendarDate from,
    CalendarDate to,
  ) => db.customSelect(
    'SELECT due_date, amount, is_income, is_paid FROM ('
    '  SELECT due_date, amount, 0 AS is_income, is_paid FROM payments'
    '    WHERE space_id = ?1 AND is_deleted = 0'
    '  UNION ALL'
    '  SELECT expected_date AS due_date, amount, 1 AS is_income, is_paid'
    '    FROM incomes WHERE space_id = ?1 AND is_deleted = 0'
    ') AS combined WHERE due_date BETWEEN ?2 AND ?3',
    variables: <Variable<Object>>[
      Variable<String>(spaceId),
      Variable<String>(from.toIso()),
      Variable<String>(to.toIso()),
    ],
    readsFrom: <ResultSetImplementation<HasResultSet, Object>>{
      db.payments,
      db.incomes,
    },
  );

  Map<CalendarDate, DayTotals> _foldByDay(List<QueryRow> rows) =>
      _fold(rows, (CalendarDate d) => d);

  Map<CalendarDate, DayTotals> _fold(
    List<QueryRow> rows,
    CalendarDate Function(CalendarDate date) bucket,
  ) {
    final Map<CalendarDate, DayTotals> out = <CalendarDate, DayTotals>{};
    for (final QueryRow row in rows) {
      final CalendarDate key = bucket(
        CalendarDate.parse(row.read<String>('due_date')),
      );
      // A floating income has no figure yet (spec 4.7). It still counts as a
      // record, so the day is not drawn as empty.
      final String? raw = row.read<String?>('amount');
      final Decimal amount = raw == null
          ? Decimal.zero
          : Decimal.parse(raw).abs();
      final bool isIncome = row.read<int>('is_income') == 1;

      out[key] = (out[key] ?? DayTotals.empty).add(
        amount,
        isIncome: isIncome,
        isPaid: row.read<int>('is_paid') == 1,
        amountKnown: raw != null,
      );
    }
    return out;
  }
}
