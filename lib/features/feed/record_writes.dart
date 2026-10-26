import 'package:drift/drift.dart' show Value;
import 'package:sielto/app/providers.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/feed/feed_model.dart';

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
  }) {
    if (!r.isIncome) return payments.setPaid(r.id, isPaid: done);
    if (done) return incomes.markReceived(r.id, actualDate: actualDate);
    return incomes.update(
      r.id,
      isPaid: const Value<bool>(false),
      actualDate: const Value<CalendarDate?>(null),
    );
  }

  Future<int> moveRecord(FeedRecord r, CalendarDate date) => r.isIncome
      ? incomes.update(r.id, expectedDate: Value<CalendarDate>(date))
      : payments.update(r.id, dueDate: Value<CalendarDate>(date));

  Future<int> setRecordOrder(FeedRecord r, int order) => r.isIncome
      ? incomes.setSortOrder(r.id, order)
      : payments.update(r.id, sortOrder: Value<int>(order));
}
