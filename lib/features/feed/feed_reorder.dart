import 'package:meta/meta.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/feed/feed_model.dart';

sealed class ReorderOutcome {
  const ReorderOutcome();
}

/// New order within the day; the whole day is renumbered.
@immutable
class ReorderWithinDay extends ReorderOutcome {
  const ReorderWithinDay(this.orderedIds);

  final List<String> orderedIds;
}

/// Dropped on another day. The date picker opens with [suggestedDate].
@immutable
class ReorderToOtherDay extends ReorderOutcome {
  const ReorderToOtherDay(this.recordId, this.suggestedDate);

  final String recordId;
  final CalendarDate suggestedDate;
}

/// In `grouped` mode a row cannot leave its type block.
class ReorderRejected extends ReorderOutcome {
  const ReorderRejected();
}

/// [insertAt] is the index after removal, as `onReorderItem` reports it.
ReorderOutcome resolveReorder({
  required List<FeedItem> items,
  required int oldIndex,
  required int insertAt,
  required FeedOrderMode orderMode,
}) {
  final FeedItem dragged = items[oldIndex];
  if (dragged is! FeedRow) return const ReorderRejected();
  final FeedRecord record = dragged.record;

  final List<FeedItem> without = List<FeedItem>.of(items)..removeAt(oldIndex);

  final FeedRow? previous = _nearestRow(without, insertAt - 1, step: -1);
  final FeedRow? next = _nearestRow(without, insertAt, step: 1);
  final CalendarDate? dropDay = _dayAt(without, insertAt);

  if (dropDay == null || dropDay != record.date) {
    return ReorderToOtherDay(
      record.id,
      _suggestDate(
        previous: previous?.record.date,
        next: next?.record.date,
        fallback: dropDay ?? record.date,
      ),
    );
  }

  if (orderMode == FeedOrderMode.grouped &&
      !_fitsItsGroup(record, previous: previous, next: next)) {
    return const ReorderRejected();
  }

  final List<String> ordered = <String>[];
  for (final FeedItem item in without) {
    if (item is FeedRow && item.record.date == record.date) {
      ordered.add(item.record.id);
    }
  }
  final int position = _positionWithinDay(without, insertAt, record.date);
  ordered.insert(position, record.id);
  return ReorderWithinDay(ordered);
}

/// Null above the first header.
CalendarDate? _dayAt(List<FeedItem> items, int insertAt) {
  for (int i = insertAt - 1; i >= 0; i--) {
    final FeedItem item = items[i];
    if (item is FeedHeader) return item.date;
  }
  return null;
}

FeedRow? _nearestRow(List<FeedItem> items, int from, {required int step}) {
  for (int i = from; i >= 0 && i < items.length; i += step) {
    final FeedItem item = items[i];
    if (item is FeedRow) return item;
    if (item is FeedHeader) return null;
  }
  return null;
}

/// The neighbouring day, or the later one when between two.
CalendarDate _suggestDate({
  required CalendarDate? previous,
  required CalendarDate? next,
  required CalendarDate fallback,
}) {
  if (previous != null && next != null) {
    return previous.isAfter(next) ? previous : next;
  }
  return previous ?? next ?? fallback;
}

/// Incomes, then mandatory, then variable. A row may sit between blocks.
bool _fitsItsGroup(
  FeedRecord record, {
  required FeedRow? previous,
  required FeedRow? next,
}) {
  final int rank = _rank(record);
  if (previous != null &&
      previous.record.date == record.date &&
      _rank(previous.record) > rank) {
    return false;
  }
  if (next != null &&
      next.record.date == record.date &&
      _rank(next.record) < rank) {
    return false;
  }
  return true;
}

int _rank(FeedRecord r) {
  if (r.isIncome) return 0;
  return r.isMandatory ? 1 : 2;
}

int _positionWithinDay(List<FeedItem> items, int insertAt, CalendarDate day) {
  int position = 0;
  for (int i = 0; i < insertAt && i < items.length; i++) {
    final FeedItem item = items[i];
    if (item is FeedRow && item.record.date == day) position++;
  }
  return position;
}
