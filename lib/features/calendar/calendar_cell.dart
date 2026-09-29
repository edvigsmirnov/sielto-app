import 'dart:ui' show PathMetric;

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
        border: switch (mark.deadline) {
          // The soft deadline's dashed border is painted below.
          DeadlineKind.hard => Border.all(color: sage.accentStrong, width: 1.5),
          DeadlineKind.soft || null => null,
        },
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
          if (mark.deadline == DeadlineKind.soft)
            Positioned.fill(
              child: CustomPaint(
                painter: _DashedRectPainter(
                  color: sage.accentStrong,
                  radius: radius,
                ),
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

/// Dashed rounded rectangle for a soft deadline.
class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final Path path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(0.75),
      );

    const double dash = 4;
    const double gap = 3;
    for (final PathMetric metric in path.computeMetrics()) {
      double start = 0;
      while (start < metric.length) {
        final double end = (start + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(start, end), paint);
        start = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) =>
      old.color != color || old.radius != radius;
}
