import 'package:drift/drift.dart' show Value;
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/freeze_guard.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/feed/feed_model.dart';
import 'package:sielto/features/payments/series_scope_dialog.dart';

/// Writes to a Feed record, payment or income alike.
extension RecordWrites on Repositories {
  Future<int> softDeleteRecord(FeedRecord r) =>
      r.isIncome ? incomes.softDelete(r.id) : payments.softDelete(r.id);

  Future<int> restoreRecord(FeedRecord r) =>
      r.isIncome ? incomes.restore(r.id) : payments.restore(r.id);

  /// Paid, or received on [actualDate]; an income needs an amount.
  Future<int> setRecordDone(
    FeedRecord r, {
    required bool done,
    CalendarDate? actualDate,
  }) => r.isIncome
      ? _setReceived(r.id, done, actualDate: actualDate)
      : payments.setPaid(r.id, isPaid: done);

  Future<int> moveRecord(FeedRecord r, CalendarDate date) => r.isIncome
      ? incomes.update(r.id, expectedDate: Value<CalendarDate>(date))
      : payments.update(r.id, dueDate: Value<CalendarDate>(date));

  Future<int> setRecordOrder(FeedRecord r, int order) => r.isIncome
      ? incomes.setSortOrder(r.id, order)
      : payments.update(r.id, sortOrder: Value<int>(order));

  /// Gives the dates of [pivot]'s series that [scope] reaches its paid status.
  /// Frozen ones keep theirs.
  Future<void> spreadPaid(
    Payment pivot,
    StatusScope scope, {
    required bool paid,
  }) async {
    final String? group = pivot.groupRecurringId;
    if (group == null) return;
    for (final Payment p in await payments.seriesOf(group)) {
      if (p.id == pivot.id ||
          p.isPaid == paid ||
          !scope.reaches(p.dueDate, pivot.dueDate)) {
        continue;
      }
      await _unlessFrozen(() => payments.setPaid(p.id, isPaid: paid));
    }
  }

  /// [spreadPaid] for a regular income; dates without an amount stay
  /// unreceived.
  Future<void> spreadReceived(
    Income pivot,
    StatusScope scope, {
    required bool received,
  }) async {
    final String? rule = pivot.recurrenceRuleId;
    if (rule == null) return;
    for (final Income i in await incomes.forRule(rule)) {
      if (i.id == pivot.id ||
          i.isPaid == received ||
          (received && i.amount == null) ||
          !scope.reaches(i.expectedDate, pivot.expectedDate)) {
        continue;
      }
      await _unlessFrozen(() => _setReceived(i.id, received));
    }
  }

  Future<int> _setReceived(
    String id,
    bool received, {
    CalendarDate? actualDate,
  }) => received
      ? incomes.markReceived(id, actualDate: actualDate)
      : incomes.update(
          id,
          isPaid: const Value<bool>(false),
          actualDate: const Value<CalendarDate?>(null),
        );

  Future<void> _unlessFrozen(Future<int> Function() write) async {
    try {
      await write();
    } on PeriodFrozen {
      return;
    }
  }
}
