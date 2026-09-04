import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';

/// One wedge: how much of the whole, and in what colour.
@immutable
class DonutSlice {
  const DonutSlice({required this.fraction, required this.color});

  /// Of the total, between 0 and 1.
  final double fraction;

  final Color color;
}

/// The ring over Analytics level 1 (design section 11).
///
/// A ring rather than a pie because the hole carries the total, which is the
/// figure the wedges are proportions of. The caller supplies the colours: they
/// are the users' own category colours, not Sage tokens, and have to survive a
/// theme change unchanged (spec 7).
class DonutChart extends StatelessWidget {
  const DonutChart({
    required this.slices,
    required this.centre,
    required this.caption,
    this.size = 116,
    super.key,
  });

  final List<DonutSlice> slices;

  /// The total, in the hole.
  final String centre;

  /// What the total is of — the range, in a word.
  final String caption;

  final double size;

  /// Ring thickness as a share of the radius.
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
          // An empty ring still draws, as the shape of an answer that is
          // simply zero.
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

  /// Twelve o'clock, in radians from three o'clock where the canvas starts.
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
