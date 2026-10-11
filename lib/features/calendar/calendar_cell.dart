import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:sielto/core/db/repositories/calendar_repository.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/calendar/day_marks.dart';

/// What a screen reader says for a day cell: the date, its sums and marks.
String describeDay(
  CalendarDate date, {
  required DayTotals? totals,
  required DayMark mark,
  required CalendarDate today,
  required MoneyFormat money,
  required DateLabels dates,
}) => <String>[
  dates.weekdayAndDate(date, reference: today),
  if (date == today) tr('calendar.legend.today'),
  if (totals case final DayTotals t when t.expenses > Decimal.zero)
    '${tr('calendar.dayExpenses')}: ${money.format(t.expenses)}',
  if (totals case final DayTotals t when t.income > Decimal.zero)
    '${tr('calendar.dayIncome')}: ${money.format(t.income)}',
  if (totals case final DayTotals t when t.hasUnknownAmount)
    tr('calendar.legend.noAmount'),
  if (mark.isHoliday)
    tr('calendar.legend.holiday')
  else if (mark.isNonWorking)
    tr('calendar.legend.nonWorking'),
  if (mark.isHighLoad) tr('calendar.legend.highLoad'),
  if (mark.isUncertainIncome) tr('calendar.legend.uncertainIncome'),
  if (mark.deadline case final DeadlineKind kind)
    tr('calendar.legend.${kind.name}Deadline'),
].join('. ');

/// A day cell's tap, long-press and spoken [label]. The menu opens at the
/// finger, or mid-cell for a screen reader.
class DayCellTap extends StatelessWidget {
  const DayCellTap({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.onHold,
    required this.child,
    this.radius = SageRadius.chip,
    super.key,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final ValueChanged<Offset> onHold;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Offset? down;
    void hold() {
      HapticFeedback.mediumImpact();
      final RenderBox box = context.findRenderObject()! as RenderBox;
      onHold(down ?? box.localToGlobal(box.size.center(Offset.zero)));
      down = null;
    }

    return Semantics(
      label: label,
      button: true,
      selected: isSelected,
      excludeSemantics: true,
      onTap: onTap,
      onLongPress: hold,
      child: InkWell(
        onTap: onTap,
        onTapDown: (TapDownDetails d) => down = d.globalPosition,
        onLongPress: hold,
        borderRadius: BorderRadius.circular(radius),
        child: child,
      ),
    );
  }
}

/// Shared by the Month and Week views. [showCalendarLegend] documents every
/// decoration.
class CellDecoration extends StatelessWidget {
  const CellDecoration({
    required this.mark,
    required this.child,
    this.isSelected = false,
    this.isToday = false,
    this.radius = SageRadius.chip,
    this.dimmed = false,
    super.key,
  });

  final DayMark mark;
  final Widget child;
  final bool isSelected;
  final bool isToday;
  final double radius;

  /// A neighbouring month's day in the Month grid: no ground, muted ink.
  final bool dimmed;

  static const double dotSize = 5;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;

    final Widget body = DecoratedBox(
      decoration: BoxDecoration(
        color: dimmed ? null : groundOf(sage, mark, isToday: isToday),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          if (mark.isUncertainIncome)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: CustomPaint(painter: _HatchPainter(color: sage.sand)),
              ),
            ),
          child,
          if (isSelected)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(
                    color: isToday ? sage.accentOn : sage.inkSecondary,
                    width: 1.5,
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
                ),
              ),
            ),
          if (mark.isHoliday)
            Positioned(
              top: 3,
              left: 3,
              child: _Dot(color: isToday ? sage.accentOn : sage.warning),
            ),
          if (mark.deadline case final DeadlineKind kind)
            Positioned(
              bottom: 2,
              left: 2,
              child: DeadlineFlag(
                kind: kind,
                size: 11,
                color: isToday ? sage.accentOn : null,
              ),
            ),
          if (mark.isHighLoad)
            Positioned(
              top: 3,
              right: 3,
              child: _Dot(color: isToday ? sage.accentOn : sage.danger),
            ),
        ],
      ),
    );

    return body;
  }

  static Color groundOf(
    SageColors sage,
    DayMark mark, {
    required bool isToday,
  }) {
    if (isToday) return sage.accent;
    if (mark.isNonWorking) return sage.warningTint;
    return sage.card;
  }

  static Color inkOf(SageColors sage, DayMark mark, {required bool isToday}) {
    if (isToday) return sage.accentOn;
    if (mark.isNonWorking) return sage.warning;
    return sage.ink;
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: CellDecoration.dotSize,
    height: CellDecoration.dotSize,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Diagonal hatching for the income-uncertainty span.
class _HatchPainter extends CustomPainter {
  const _HatchPainter({required this.color});

  final Color color;

  static const double _spacing = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color.withValues(alpha: 0.75)
      ..strokeWidth = 1.5;
    for (double x = -size.height; x < size.width; x += _spacing) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_HatchPainter old) => old.color != color;
}

/// Filled for a hard deadline, outlined for a soft one.
class DeadlineFlag extends StatelessWidget {
  const DeadlineFlag({
    required this.kind,
    this.size = 20,
    this.color,
    super.key,
  });

  final DeadlineKind kind;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Icon(
    kind == DeadlineKind.hard ? Icons.flag : Icons.outlined_flag,
    size: size,
    color: color ?? context.sage.danger,
  );
}
