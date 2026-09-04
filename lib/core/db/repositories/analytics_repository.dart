import 'dart:isolate';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:meta/meta.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';

/// One raw payment as Analytics reads it: what it groups under, how it is
/// spelt, what it cost.
///
/// Strings, not `Decimal`: these cross an isolate boundary, and only types the
/// standard message codec understands may. The parse happens on the far side.
typedef AnalyticsRow = ({String key, String label, String amount});

/// One line of an Analytics level: what it is, what it cost, how often.
@immutable
class AnalyticsSlice {
  const AnalyticsSlice({
    required this.key,
    required this.label,
    required this.total,
    required this.count,
  });

  /// The grouping key. A category id at level 1, `lower(trim(title))` at
  /// level 2 — never the label, which is only the spelling chosen for display.
  final String key;

  final String label;
  final Decimal total;
  final int count;

  /// Mean per record. The level-3 figure (spec 8.2).
  Decimal get average => count == 0
      ? Decimal.zero
      : (total / Decimal.fromInt(count)).toDecimal(scaleOnInfinitePrecision: 2);
}

/// Analytics' reads (spec 8.2).
///
/// Calendar ranges, never `budget_period_id`: the Dashboard and the Feed are
/// tied to the income cycle and Analytics deliberately is not. The two
/// therefore disagree about totals for the same-looking month, which is why
/// every screen here states its range (plan G9).
///
/// Incomes are absent by design — all three levels are about where money goes.
class AnalyticsRepository {
  AnalyticsRepository({required this.db});

  /// The key a payment with no category groups under. Not a real id, so it
  /// cannot collide with one: ids are UUIDv4.
  static const String uncategorisedKey = '';

  final AppDatabase db;

  /// Level 1: totals per category over [from]..[to], largest first.
  ///
  /// The slice label is the category id — the display name lives in
  /// `categories` and is resolved by the screen, which also has to handle a
  /// category that was since deleted (spec 7).
  ///
  /// Uncategorised payments make a slice of their own rather than being
  /// dropped, or the levels would disagree with the Feed about what a month
  /// cost.
  Future<List<AnalyticsSlice>> byCategory({
    required String spaceId,
    required CalendarDate from,
    required CalendarDate to,
    ExpenseType? expenseType,
  }) => _slices(
    // Both columns are the id: level 1 has no spelling to choose between.
    columns:
        "coalesce(category_id, '$uncategorisedKey') AS grouping_key, "
        "coalesce(category_id, '$uncategorisedKey') AS label",
    spaceId: spaceId,
    from: from,
    to: to,
    expenseType: expenseType,
  );

  /// Levels 2 and 3: totals and averages per title inside one category.
  ///
  /// Grouped by `lower(trim(title))` and labelled with the most frequent
  /// spelling, so "Klarna" and "klarna " are one line. Full normalisation is
  /// deliberately not attempted — typical divergence is what this removes, and
  /// the autocomplete on the payment form is the other half of the defence.
  ///
  /// A null [categoryId] means the uncategorised slice, not "any category":
  /// level 2 is always reached through one slice of level 1.
  Future<List<AnalyticsSlice>> byTitle({
    required String spaceId,
    required CalendarDate from,
    required CalendarDate to,
    required String? categoryId,
    ExpenseType? expenseType,
  }) => _slices(
    columns: 'lower(trim(title)) AS grouping_key, title AS label',
    spaceId: spaceId,
    from: from,
    to: to,
    expenseType: expenseType,
    category: (id: categoryId, present: true),
  );

  /// One query, then folded in Dart.
  ///
  /// The sum cannot happen in SQL: money is TEXT and `SUM` over it would go
  /// through REAL. SQL does the filtering, which is where the cost is.
  ///
  /// The optional filters are appended as clauses rather than passed as
  /// nullable placeholders, because drift's `Variable` does not admit null as
  /// a bound value.
  Future<List<AnalyticsSlice>> _slices({
    required String columns,
    required String spaceId,
    required CalendarDate from,
    required CalendarDate to,
    ExpenseType? expenseType,
    ({String? id, bool present})? category,
  }) async {
    final List<String> clauses = <String>[
      'space_id = ?',
      'is_deleted = 0',
      'due_date BETWEEN ? AND ?',
    ];
    final List<Variable<Object>> variables = <Variable<Object>>[
      Variable<String>(spaceId),
      Variable<String>(from.toIso()),
      Variable<String>(to.toIso()),
    ];

    if (category != null) {
      final String? id = category.id;
      if (id == null) {
        clauses.add('category_id IS NULL');
      } else {
        clauses.add('category_id = ?');
        variables.add(Variable<String>(id));
      }
    }
    if (expenseType != null) {
      clauses.add('expense_type = ?');
      variables.add(Variable<String>(expenseType.name));
    }

    final List<QueryRow> rows = await db
        .customSelect(
          'SELECT $columns, amount FROM payments '
          'WHERE ${clauses.join(' AND ')}',
          variables: variables,
          readsFrom: <ResultSetImplementation<HasResultSet, Object>>{
            db.payments,
          },
        )
        .get();

    final List<AnalyticsRow> raw = <AnalyticsRow>[
      for (final QueryRow row in rows)
        (
          key: row.read<String>('grouping_key'),
          label: row.read<String>('label'),
          amount: row.read<String>('amount'),
        ),
    ];

    // Above the threshold the fold moves off the main thread; below it, the
    // isolate spawn and the message copy cost more than the work (spec 8.2).
    // `Isolate.run` rather than Flutter's `compute` so nothing under core/db
    // needs a Flutter import.
    return raw.length > isolateRowThreshold
        ? Isolate.run(() => foldSlices(raw))
        : foldSlices(raw);
  }

  /// Rows above which the fold is handed to an isolate (spec 8.2).
  ///
  /// Approximate and named here rather than inlined, because the spec is
  /// explicit that it wants profiling against real data and not a blanket
  /// rule.
  static const int isolateRowThreshold = 500;
}

/// Collapses raw rows into one slice per grouping key, largest total first.
///
/// Pure and top-level: an isolate body may only close over sendable state,
/// and this closes over nothing but its argument.
List<AnalyticsSlice> foldSlices(List<AnalyticsRow> rows) {
  final Map<String, Decimal> totals = <String, Decimal>{};
  final Map<String, int> counts = <String, int>{};
  final Map<String, Map<String, int>> labels = <String, Map<String, int>>{};

  for (final AnalyticsRow row in rows) {
    totals[row.key] =
        (totals[row.key] ?? Decimal.zero) + Decimal.parse(row.amount);
    counts[row.key] = (counts[row.key] ?? 0) + 1;
    final Map<String, int> seen = labels.putIfAbsent(
      row.key,
      () => <String, int>{},
    );
    seen[row.label] = (seen[row.label] ?? 0) + 1;
  }

  final List<AnalyticsSlice> slices = <AnalyticsSlice>[
    for (final String key in totals.keys)
      AnalyticsSlice(
        key: key,
        label: _mostFrequent(labels[key]!),
        total: totals[key]!,
        count: counts[key]!,
      ),
  ];
  // Ties break on the label so the order does not shuffle between rebuilds.
  slices.sort((AnalyticsSlice a, AnalyticsSlice b) {
    final int byTotal = b.total.compareTo(a.total);
    return byTotal != 0 ? byTotal : a.label.compareTo(b.label);
  });
  return slices;
}

/// The spelling used most often, and the alphabetically first of a tie.
String _mostFrequent(Map<String, int> spellings) {
  String best = spellings.keys.first;
  for (final MapEntry<String, int> e in spellings.entries) {
    final int bestCount = spellings[best]!;
    if (e.value > bestCount ||
        (e.value == bestCount && e.key.compareTo(best) < 0)) {
      best = e.key;
    }
  }
  return best;
}
