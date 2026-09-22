import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/calendar/calendar_cell.dart';
import 'package:sielto/features/calendar/day_marks.dart';

/// What each colour and mark on a day cell means, drawn with the cell's own
/// decoration so the key cannot drift from the grid.
Future<void> showCalendarLegend(
  BuildContext context, {
  required BudgetMode mode,
  required MoneyFormat money,
  required Decimal? loadThreshold,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (BuildContext sheet) {
    final SageColors sage = sheet.sage;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          SageSpace.gutter,
          0,
          SageSpace.gutter,
          SageSpace.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              tr('calendar.legend.title'),
              style: Theme.of(sheet).textTheme.titleSmall,
            ),
            const SizedBox(height: SageSpace.md),
            _Entry(
              figure: ('−', sage.danger),
              label: tr('calendar.legend.expenses'),
            ),
            _Entry(
              figure: ('+', sage.accentStrong),
              label: tr('calendar.legend.income'),
            ),
            _Entry(
              figure: ('·', sage.inkLabel),
              label: tr('calendar.legend.noAmount'),
            ),
            _Entry(
              figure: ('1', sage.accentStrong),
              label: tr('calendar.legend.today'),
            ),
            _Entry(isSelected: true, label: tr('calendar.legend.selected')),
            _Entry(
              mark: const DayMark(isNonWorking: true),
              label: tr('calendar.legend.nonWorking'),
            ),
            _Entry(
              mark: const DayMark(isNonWorking: true, isHoliday: true),
              label: tr('calendar.legend.holiday'),
            ),
            _Entry(
              mark: const DayMark(isHighLoad: true),
              label: loadThreshold == null
                  ? tr('calendar.legend.highLoad')
                  : tr(
                      'calendar.legend.highLoadOver',
                      namedArgs: <String, String>{
                        'amount': money.format(loadThreshold),
                      },
                    ),
            ),
            if (mode == BudgetMode.incomeDriven)
              _Entry(
                mark: const DayMark(isUncertainIncome: true),
                label: tr('calendar.legend.uncertainIncome'),
              ),
            if (mode == BudgetMode.budget) ...<Widget>[
              _Entry(
                mark: const DayMark(deadline: DeadlineKind.hard),
                label: tr('calendar.legend.hardDeadline'),
              ),
              _Entry(
                mark: const DayMark(deadline: DeadlineKind.soft),
                label: tr('calendar.legend.softDeadline'),
              ),
            ],
          ],
        ),
      ),
    );
  },
);

class _Entry extends StatelessWidget {
  const _Entry({
    required this.label,
    this.mark = DayMark.none,
    this.figure,
    this.isSelected = false,
  });

  final String label;
  final DayMark mark;
  final (String, Color)? figure;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final (String, Color)? f = figure;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SageSpace.xs),
      child: Row(
        children: <Widget>[
          SizedBox.square(
            dimension: 32,
            child: CellDecoration(
              mark: mark,
              isSelected: isSelected,
              child: Center(
                child: f == null
                    ? null
                    : Text(
                        f.$1,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: f.$2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: SageSpace.md),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
