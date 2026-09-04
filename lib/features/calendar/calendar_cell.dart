import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/features/calendar/day_marks.dart';

/// How a decorated cell is drawn (design section 7).
///
/// One place for the whole scheme, so the Month grid and the Week rows decorate
/// the same day the same way:
///
///   - non-working day: a `warningAccent` wash, the figures in `warning`
///   - holiday or custom day: that wash plus a corner dot, which is what
///     separates a public holiday from an ordinary weekend
///   - high load: a `danger` dot in the other corner
///   - income uncertainty: diagonal `sand` hatching across the cell
///   - deadline: a border — solid for hard, dashed for soft (spec 4.8)
///   - selected: the solid `accent` fill, which overrides every wash
///
/// The corners carry the two dots and the border carries the deadline, so no
/// two decorations compete for the same pixels. All of it comes out of the
/// existing token set; the plan considered a dedicated `loadTint` pair and it
/// turned out not to be needed, because load is a dot rather than a wash.
class CellDecoration extends StatelessWidget {
  const CellDecoration({
    required this.mark,
    required this.child,
    this.isSelected = false,
    this.radius = SageRadius.chip,
    this.dimmed = false,
    super.key,
  });

  final DayMark mark;
  final Widget child;
  final bool isSelected;
  final double radius;

  /// A day from a neighbouring month in the Month grid: present, and clearly
  /// not part of what is being read.
  final bool dimmed;

  /// The corner marker, and the room the cell has to leave for it.
  static const double dotSize = 5;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;

    final Widget body = DecoratedBox(
      decoration: BoxDecoration(
        color: groundOf(sage, mark, isSelected: isSelected),
        borderRadius: BorderRadius.circular(radius),
        border: switch (mark.deadline) {
          // Solid against dashed, so a hard deadline is visibly the one that
          // refuses records (spec 4.8). The dashed one is painted below.
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
          if (mark.isHoliday)
            Positioned(
              top: 3,
              left: 3,
              child: _Dot(color: isSelected ? sage.accentOn : sage.warning),
            ),
          if (mark.isHighLoad)
            Positioned(
              top: 3,
              right: 3,
              child: _Dot(color: isSelected ? sage.accentOn : sage.danger),
            ),
        ],
      ),
    );

    return dimmed ? Opacity(opacity: 0.35, child: body) : body;
  }

  /// The cell ground. Selection wins over every wash, because it is the one
  /// thing the user just did.
  static Color groundOf(
    SageColors sage,
    DayMark mark, {
    required bool isSelected,
  }) {
    if (isSelected) return sage.accent;
    if (mark.isNonWorking) return sage.warningTint;
    return sage.card;
  }

  /// The ink for a cell's own figures, following the ground.
  static Color inkOf(
    SageColors sage,
    DayMark mark, {
    required bool isSelected,
  }) {
    if (isSelected) return sage.accentOn;
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

/// Diagonal hatching for the income-uncertainty span (spec 5.2, 8.1).
///
/// Stripes rather than a flat tint: the span is not a state of the day, it is a
/// "might be here", and a hatch reads as provisional where a fill reads as
/// settled.
class _HatchPainter extends CustomPainter {
  const _HatchPainter({required this.color});

  final Color color;

  static const double _spacing = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      // The token at low opacity: the hatch sits under the figures and must not
      // compete with them for contrast.
      ..color = color.withValues(alpha: 0.45)
      ..strokeWidth = 1;
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

/// A dashed rounded rectangle: the soft deadline's border.
///
/// Flutter strokes no dashed border of its own, and `DashedButton` in the UI
/// kit paints an outline of a whole card — this one takes a cell's radius and
/// stroke.
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
