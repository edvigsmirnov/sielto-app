import 'dart:isolate';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:meta/meta.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';

/// A payment row for Analytics. Amount is a string: rows cross an isolate
/// boundary.
typedef AnalyticsRow = ({String key, String label, String amount});

@immutable
class AnalyticsSlice {
  const AnalyticsSlice({
    required this.key,
    required this.label,
    required this.total,
    required this.count,
  });

  /// Category id at level 1, `lower(trim(title))` at level 2.
  final String key;

  final String label;
  final Decimal total;
  final int count;

  Decimal get average => count == 0
      ? Decimal.zero
      : (total / Decimal.fromInt(count)).toDecimal(scaleOnInfinitePrecision: 2);
}

/// Analytics reads by calendar range, never by `budget_period_id`. Payments
/// only.
class AnalyticsRepository {
  AnalyticsRepository({required this.db});

  /// Groups payments without a category.
  static const String uncategorisedKey = '';

  final AppDatabase db;

  /// Level 1: totals per category over [from]..[to], largest first. Label is the
  /// category id. Uncategorised payments form their own slice.
  Future<List<AnalyticsSlice>> byCategory({
    required String spaceId,
    required CalendarDate from,
    required CalendarDate to,
    ExpenseType? expenseType,
  }) => _slices(
    columns:
        "coalesce(category_id, '$uncategorisedKey') AS grouping_key, "
        "coalesce(category_id, '$uncategorisedKey') AS label",
    spaceId: spaceId,
    from: from,
    to: to,
    expenseType: expenseType,
  );

  /// Levels 2 and 3, grouped by `lower(trim(title))` under the most frequent
  /// spelling. Null [categoryId] is the uncategorised slice.
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

  /// SQL filters, Dart sums. Optional filters are appended as clauses: drift's
  /// `Variable` rejects null.
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

    // `Isolate.run`, not `compute`: core/db has no Flutter import.
    return raw.length > isolateRowThreshold
        ? Isolate.run(() => foldSlices(raw))
        : foldSlices(raw);
  }

  /// Rows above which the fold runs in an isolate.
  static const int isolateRowThreshold = 5000;
}

/// One slice per grouping key, largest total first. Top-level so an isolate can
/// run it.
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
  slices.sort((AnalyticsSlice a, AnalyticsSlice b) {
    final int byTotal = b.total.compareTo(a.total);
    return byTotal != 0 ? byTotal : a.label.compareTo(b.label);
  });
  return slices;
}

/// Ties go to the alphabetically first spelling.
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
