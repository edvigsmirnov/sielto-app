import 'package:decimal/decimal.dart';
import 'package:meta/meta.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';

/// A Feed row, from a payment or an income. Unlike `LedgerEntry`, the amount
/// may be unknown.
@immutable
class FeedRecord {
  const FeedRecord({
    required this.id,
    required this.date,
    required this.title,
    required this.amount,
    required this.isIncome,
    required this.isPaid,
    required this.sortOrder,
    this.expenseType,
    this.categoryId,
    this.notes,
    this.groupRecurringId,
    this.budgetPeriodId,
  });

  factory FeedRecord.fromPayment(Payment p) => FeedRecord(
    id: p.id,
    date: p.dueDate,
    title: p.title,
    amount: p.amount,
    isIncome: false,
    isPaid: p.isPaid,
    sortOrder: p.sortOrder,
    expenseType: p.expenseType,
    categoryId: p.categoryId,
    notes: p.notes,
    groupRecurringId: p.groupRecurringId,
    budgetPeriodId: p.budgetPeriodId,
  );

  factory FeedRecord.fromIncome(Income i) => FeedRecord(
    id: i.id,
    date: i.expectedDate,
    title: i.title,
    // Null: amount not known yet.
    amount: i.amount,
    isIncome: true,
    isPaid: i.isPaid,
    sortOrder: i.sortOrder,
    notes: i.notes,
    budgetPeriodId: i.budgetPeriodId,
  );

  final String id;
  final CalendarDate date;
  final String title;
  final Decimal? amount;
  final bool isIncome;
  final bool isPaid;
  final int sortOrder;
  final ExpenseType? expenseType;
  final String? categoryId;
  final String? notes;
  final String? groupRecurringId;

  /// Null until a recompute binds it.
  final String? budgetPeriodId;

  FeedRecord withSortOrder(int order) => FeedRecord(
    id: id,
    date: date,
    title: title,
    amount: amount,
    isIncome: isIncome,
    isPaid: isPaid,
    sortOrder: order,
    expenseType: expenseType,
    categoryId: categoryId,
    notes: notes,
    groupRecurringId: groupRecurringId,
    budgetPeriodId: budgetPeriodId,
  );

  bool get isMandatory => expenseType == ExpenseType.mandatory;

  /// Incomes, then mandatory, then variable.
  int get groupRank => isIncome ? 0 : (isMandatory ? 1 : 2);

  /// Unpaid and due before today. Incomes are never overdue.
  bool isOverdue(CalendarDate today) =>
      !isIncome && !isPaid && date.isBefore(today);
}

/// `grouped`: type block, then `sort_order`. `free`: `sort_order`. Id breaks
/// ties.
int compareInDay(FeedRecord a, FeedRecord b, FeedOrderMode mode) {
  if (mode == FeedOrderMode.grouped) {
    final int byGroup = a.groupRank.compareTo(b.groupRank);
    if (byGroup != 0) return byGroup;
  }
  final int byOrder = a.sortOrder.compareTo(b.sortOrder);
  if (byOrder != 0) return byOrder;
  return a.id.compareTo(b.id);
}

sealed class FeedItem {
  const FeedItem();

  /// Stable across rebuilds for reorder and dismiss.
  String get key;
}

class FeedHeader extends FeedItem {
  const FeedHeader.day(this.date);

  final CalendarDate date;

  @override
  String get key => 'header:${date.toIso()}';
}

class FeedRow extends FeedItem {
  const FeedRow(this.record, {required this.isCovered});

  final FeedRecord record;

  /// False for this row and every expense after it.
  final bool isCovered;

  @override
  String get key => 'row:${record.id}';
}

/// Where the money runs out. One per cycle, keyed by its row.
class FeedCutoff extends FeedItem {
  const FeedCutoff(this.date, this.entryId);

  final CalendarDate date;
  final String entryId;

  @override
  String get key => 'cutoff:$entryId';
}

/// Chronological; overdue rows stay on their due day.
List<FeedItem> buildFeedItems({
  required List<FeedRecord> records,
  required FeedOrderMode orderMode,
  Map<String, bool> coverage = const <String, bool>{},

  /// Row id to the side of the row where the cutoff falls.
  Map<String, bool> moneyEndsAt = const <String, bool>{},

  /// Gets a heading even with nothing on it.
  CalendarDate? today,
}) {
  final Map<String, List<FeedRecord>> byDay = <String, List<FeedRecord>>{};
  for (final FeedRecord r in records) {
    byDay.putIfAbsent(r.date.toIso(), () => <FeedRecord>[]).add(r);
  }
  if (today != null && records.isNotEmpty) {
    byDay.putIfAbsent(today.toIso(), () => <FeedRecord>[]);
  }

  final List<FeedItem> items = <FeedItem>[];
  final List<String> days = byDay.keys.toList()..sort();
  for (final String day in days) {
    items.add(FeedHeader.day(CalendarDate.parse(day)));
    final List<FeedRecord> rows = byDay[day]!
      ..sort((FeedRecord a, FeedRecord b) => compareInDay(a, b, orderMode));
    for (final FeedRecord r in rows) {
      // True: below the row. False: above.
      final bool? below = moneyEndsAt[r.id];
      if (below == false) items.add(FeedCutoff(r.date, r.id));
      items.add(FeedRow(r, isCovered: coverage[r.id] ?? true));
      if (below == true) items.add(FeedCutoff(r.date, r.id));
    }
  }

  return items;
}
