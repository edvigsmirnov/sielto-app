import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/features/calendar/day_marks.dart';

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

  /// A neighbouring month's day in the Month grid.
  final bool dimmed;

  static const double dotSize = 5;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;

    final Widget body = DecoratedBox(
      decoration: BoxDecoration(
        color: groundOf(sage, mark, isToday: isToday),
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

    return dimmed ? Opacity(opacity: 0.35, child: body) : body;
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
