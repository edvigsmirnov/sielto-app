import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/calendar/calendar_scope.dart';

/// Picks a date at the grain of [view] (spec 8.1): a day, a week of a month,
/// a month of a year, or a year.
Future<CalendarDate?> pickCalendarDate(
  BuildContext context, {
  required CalendarView view,
  required CalendarDate selected,
  required CalendarDate today,
}) async {
  final int firstYear = today.year - 10;
  final int lastYear = today.year + 10;

  if (view == CalendarView.day) {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selected.toUtcMidnight(),
      firstDate: DateTime.utc(firstYear),
      lastDate: DateTime.utc(lastYear, 12, 31),
    );
    return picked == null ? null : CalendarDate.fromDateTime(picked);
  }

  if (view == CalendarView.year) {
    return showDialog<CalendarDate>(
      context: context,
      builder: (BuildContext dialog) => AlertDialog(
        content: SizedBox(
          width: 300,
          height: 300,
          child: YearPicker(
            firstDate: DateTime.utc(firstYear),
            lastDate: DateTime.utc(lastYear),
            selectedDate: selected.toUtcMidnight(),
            currentDate: today.toUtcMidnight(),
            onChanged: (DateTime year) =>
                Navigator.of(dialog)
                    .pop(selected.addMonths((year.year - selected.year) * 12)),
          ),
        ),
      ),
    );
  }

  return showDialog<CalendarDate>(
    context: context,
    builder: (BuildContext dialog) => AlertDialog(
      contentPadding: const EdgeInsets.all(SageSpace.md),
      content: SizedBox(
        width: 300,
        child: _GrainPicker(
          weeks: view == CalendarView.week,
          selected: selected,
          firstYear: firstYear,
          lastYear: lastYear,
        ),
      ),
    ),
  );
}

/// Month view: a year stepper over twelve months. Week view: a month stepper
/// over that month's weeks.
class _GrainPicker extends StatefulWidget {
  const _GrainPicker({
    required this.weeks,
    required this.selected,
    required this.firstYear,
    required this.lastYear,
  });

  final bool weeks;
  final CalendarDate selected;
  final int firstYear;
  final int lastYear;

  @override
  State<_GrainPicker> createState() => _GrainPickerState();
}

class _GrainPickerState extends State<_GrainPicker> {
  late CalendarDate _page = widget.selected.firstOfMonth;

  void _step(int by) =>
      setState(() => _page = _page.addMonths(widget.weeks ? by : by * 12));

  @override
  Widget build(BuildContext context) {
    final DateLabels dates = DateLabels(context.locale.toString());
    final bool canBack = widget.weeks
        ? _page.addMonths(-1).year >= widget.firstYear
        : _page.year > widget.firstYear;
    final bool canForward = widget.weeks
        ? _page.addMonths(1).year <= widget.lastYear
        : _page.year < widget.lastYear;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            IconButton(
              onPressed: canBack ? () => _step(-1) : null,
              icon: const Icon(Icons.chevron_left),
              tooltip: tr('calendar.previous'),
            ),
            Expanded(
              child: Text(
                widget.weeks ? dates.monthYear(_page) : '${_page.year}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            IconButton(
              onPressed: canForward ? () => _step(1) : null,
              icon: const Icon(Icons.chevron_right),
              tooltip: tr('calendar.next'),
            ),
          ],
        ),
        const SizedBox(height: SageSpace.sm),
        if (widget.weeks)
          for (final CalendarDate monday in _weeksOf(_page))
            _Choice(
              // Both months spelt out, so every row reads alike rather than
              // only the two that cross a month.
              label:
                  '${dates.dayMonth(monday)} – '
                  '${dates.dayMonth(monday.addDays(6))}',
              isSelected: widget.selected.startOfWeek == monday,
              onTap: () => Navigator.of(context).pop(monday),
            )
        else
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            childAspectRatio: 2.2,
            physics: const NeverScrollableScrollPhysics(),
            children: <Widget>[
              for (int m = 1; m <= 12; m++)
                _Choice(
                  label: dates.monthShort(CalendarDate(_page.year, m, 1)),
                  isSelected:
                      widget.selected.year == _page.year &&
                      widget.selected.month == m,
                  onTap: () => Navigator.of(context).pop(
                    widget.selected.addMonths(
                      (_page.year - widget.selected.year) * 12 +
                          m -
                          widget.selected.month,
                    ),
                  ),
                ),
            ],
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('common.cancel')),
          ),
        ),
      ],
    );
  }

  /// Every week that has a day in [month], by its Monday.
  static List<CalendarDate> _weeksOf(CalendarDate month) => <CalendarDate>[
    for (
      CalendarDate d = month.firstOfMonth.startOfWeek;
      !d.isAfter(month.lastOfMonth);
      d = d.addDays(7)
    )
      d,
  ];
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: isSelected ? sage.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(SageRadius.chip),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SageRadius.chip),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: SageSpace.sm),
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: isSelected ? sage.accentOn : sage.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
