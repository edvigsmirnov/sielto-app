import 'package:meta/meta.dart';
import 'package:sielto/domain/schedule/income_schedule.dart';
import 'package:sielto/domain/schedule/income_window.dart';
import 'package:sielto/domain/schedule/working_days.dart';
import 'package:sielto/domain/value/calendar_date.dart';

@immutable
class AnchorSchedule {
  const AnchorSchedule({required this.ruleId, required this.schedule});

  final String ruleId;
  final IncomeSchedule schedule;
}

/// A computed period, before it becomes a `budget_periods` row.
@immutable
class MaterializedPeriod {
  const MaterializedPeriod({
    required this.startDate,
    required this.endDate,
    required this.anchorDate,
    required this.windowStart,
    required this.windowEnd,
    required this.ruleIds,
  });

  final CalendarDate startDate;

  /// Inclusive; the day before the next anchor. Null only for the last period.
  final CalendarDate? endDate;

  final CalendarDate anchorDate;
  final CalendarDate windowStart;
  final CalendarDate windowEnd;

  /// More than one when anchors coincide and periods merge.
  final List<String> ruleIds;

  bool get isMerged => ruleIds.length > 1;

  /// Inclusive: a one-day period has length 1.
  int? get lengthInDays =>
      endDate == null ? null : startDate.daysUntil(endDate!) + 1;

  @override
  String toString() =>
      'MaterializedPeriod($startDate..${endDate ?? '-'}, '
      'anchor $anchorDate, rules $ruleIds)';
}

/// Anchor schedules to periods `[anchor, next anchor - 1]`. A payment on the
/// next anchor's date belongs to the next period.
abstract final class PeriodMaterializer {
  /// Default number of periods ahead.
  static const int horizonPeriods = 6;

  /// Periods covering [from] and the next [count] anchors. Anchors on the same
  /// date merge into one period.
  static List<MaterializedPeriod> materialize({
    required List<AnchorSchedule> anchors,
    required CalendarDate from,
    required WorkingDayCalendar calendar,
    int count = horizonPeriods,
  }) {
    if (anchors.isEmpty) return const <MaterializedPeriod>[];

    // One extra anchor gives the last period its end.
    final List<_Anchor> resolved = _anchorsFrom(
      anchors: anchors,
      from: from,
      calendar: calendar,
      needed: count + 1,
    );
    if (resolved.isEmpty) return const <MaterializedPeriod>[];

    final List<MaterializedPeriod> periods = <MaterializedPeriod>[];
    for (int i = 0; i < resolved.length && periods.length < count; i++) {
      final _Anchor current = resolved[i];
      final _Anchor? next = i + 1 < resolved.length ? resolved[i + 1] : null;
      periods.add(
        MaterializedPeriod(
          startDate: current.date,
          endDate: next?.date.addDays(-1),
          anchorDate: current.date,
          windowStart: current.windowStart,
          windowEnd: current.windowEnd,
          ruleIds: current.ruleIds,
        ),
      );
    }
    return periods;
  }

  /// True when only [remaining] periods are left ahead of [today].
  static bool needsExtension(
    List<MaterializedPeriod> periods,
    CalendarDate today, {
    int threshold = 2,
  }) {
    final int ahead = periods
        .where((MaterializedPeriod p) => !p.startDate.isBefore(today))
        .length;
    return ahead <= threshold;
  }

  /// Anchors in date order, coincident ones merged.
  static List<_Anchor> _anchorsFrom({
    required List<AnchorSchedule> anchors,
    required CalendarDate from,
    required WorkingDayCalendar calendar,
    required int needed,
  }) {
    final Map<String, _Anchor> byDate = <String, _Anchor>{};

    // Starts a month early: a late schedule can resolve into this month.
    int year = from.year;
    int month = from.month - 1;
    if (month == 0) {
      month = 12;
      year -= 1;
    }

    // Guard against a schedule that never lands ahead of `from`.
    const int maxMonths = 120;
    for (int i = 0; i < maxMonths && byDate.length < needed + 2; i++) {
      for (final AnchorSchedule anchor in anchors) {
        final IncomeWindow window = anchor.schedule.resolveFor(
          year,
          month,
          calendar: calendar,
        );
        final String key = window.anchorDate.toIso();
        final _Anchor? existing = byDate[key];
        if (existing == null) {
          byDate[key] = _Anchor(
            date: window.anchorDate,
            windowStart: window.windowStart,
            windowEnd: window.windowEnd,
            ruleIds: <String>[anchor.ruleId],
          );
        } else {
          existing.ruleIds.add(anchor.ruleId);
          byDate[key] = existing.widenedTo(window);
        }
      }
      month++;
      if (month == 13) {
        month = 1;
        year++;
      }
    }

    final List<_Anchor> sorted = byDate.values.toList()
      ..sort((_Anchor a, _Anchor b) => a.date.compareTo(b.date));

    final int startIndex = sorted.lastIndexWhere(
      (_Anchor a) => !a.date.isAfter(from),
    );
    return sorted.sublist(startIndex < 0 ? 0 : startIndex);
  }
}

class _Anchor {
  _Anchor({
    required this.date,
    required this.windowStart,
    required this.windowEnd,
    required this.ruleIds,
  });

  final CalendarDate date;
  final CalendarDate windowStart;
  final CalendarDate windowEnd;
  final List<String> ruleIds;

  /// The union of both windows.
  _Anchor widenedTo(IncomeWindow other) => _Anchor(
    date: date,
    windowStart: other.windowStart.isBefore(windowStart)
        ? other.windowStart
        : windowStart,
    windowEnd: other.windowEnd.isAfter(windowEnd) ? other.windowEnd : windowEnd,
    ruleIds: ruleIds,
  );
}
