import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';

@immutable
class DonutSlice {
  const DonutSlice({required this.fraction, required this.color});

  /// Share of the total, 0 to 1.
  final double fraction;

  final Color color;
}

/// Ring chart with the total in the hole. Colours are category colours, not
/// tokens.
class DonutChart extends StatelessWidget {
  const DonutChart({
    required this.slices,
    required this.centre,
    required this.caption,
    this.size = 116,
    super.key,
  });

  final List<DonutSlice> slices;

  final String centre;

  /// What the total covers.
  final String caption;

  final double size;

  /// Share of the radius.
  static const double _thickness = 0.28;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DonutPainter(
          slices: slices,
          // An empty ring still draws.
          empty: sage.hairline,
          thickness: _thickness,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                centre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleSmall,
              ),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.slices,
    required this.empty,
    required this.thickness,
  });

  final List<DonutSlice> slices;
  final Color empty;
  final double thickness;

  /// Twelve o'clock.
  static const double _start = -pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.shortestSide / 2;
    final double stroke = radius * thickness;
    final Rect ring = Rect.fromCircle(
      center: Offset(radius, radius),
      radius: radius - stroke / 2,
    );
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    canvas.drawArc(ring, 0, 2 * pi, false, paint..color = empty);

    double from = _start;
    for (final DonutSlice slice in slices) {
      final double sweep = slice.fraction * 2 * pi;
      canvas.drawArc(ring, from, sweep, false, paint..color = slice.color);
      from += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.empty != empty ||
      old.thickness != thickness ||
      old.slices.length != slices.length ||
      Iterable<int>.generate(slices.length).any(
        (int i) =>
            old.slices[i].fraction != slices[i].fraction ||
            old.slices[i].color != slices[i].color,
      );
}
