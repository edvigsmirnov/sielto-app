import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';

/// Loading indicator: a leaf splits into a whirl of leaves and gathers back.
class LeafLoader extends StatefulWidget {
  const LeafLoader({this.size = 88, this.onBrand = false, super.key});

  final double size;

  /// Light on [SageBrand.night], regardless of theme.
  final bool onBrand;

  static const Duration period = Duration(milliseconds: 3200);

  @override
  State<LeafLoader> createState() => _LeafLoaderState();
}

class _LeafLoaderState extends State<LeafLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: LeafLoader.period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return Semantics(
      label: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(
            painter: _WhirlPainter(
              progress: _controller,
              leaf: widget.onBrand ? SageBrand.leaf : sage.accentStrong,
              trail: widget.onBrand
                  ? SageBrand.leaf.withValues(alpha: 0.6)
                  : sage.accent,
              vein: widget.onBrand ? SageBrand.night : sage.surface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Unit length, pointing up, centred on the origin.
Path leafPath() => Path()
  ..moveTo(0, 0.5)
  ..cubicTo(-0.44, 0.3, -0.36, -0.3, 0, -0.5)
  ..cubicTo(0.36, -0.3, 0.44, 0.3, 0, 0.5)
  ..close();

class _WhirlPainter extends CustomPainter {
  _WhirlPainter({
    required this.progress,
    required this.leaf,
    required this.trail,
    required this.vein,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color leaf;
  final Color trail;
  final Color vein;

  static const int _count = 5;
  static final Path _leaf = leafPath();

  /// 0 is one leaf, 1 the full whirl.
  static double _spread(double t) {
    if (t < 0.1) return 0;
    if (t < 0.24) return Curves.easeInOut.transform((t - 0.1) / 0.14);
    if (t < 0.78) return 1;
    if (t < 0.92) return 1 - Curves.easeInOut.transform((t - 0.78) / 0.14);
    return 0;
  }

  /// Whole turns, so the cycle loops seamlessly.
  static double _spin(double t) {
    if (t <= 0.06) return 0;
    if (t >= 0.96) return 6 * math.pi;
    return 6 * math.pi * Curves.easeInOutSine.transform((t - 0.06) / 0.9);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double t = progress.value;
    final double spread = _spread(t);
    final double spin = _spin(t);
    final double unit = size.shortestSide;
    final Offset centre = size.center(Offset.zero);

    final Paint paint = Paint()..isAntiAlias = true;
    final Paint rib = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = vein.withValues(alpha: 0.7);
    // Drawn back to front; leaf 0 is the one at rest.
    for (int i = _count - 1; i >= 0; i--) {
      final double share = i / _count;
      final double angle = spin + share * 2 * math.pi;
      final double radius = spread * unit * (0.14 + 0.2 * (1 - share));
      final double scale = unit * (0.7 - 0.42 * spread) * (1 - 0.12 * share);
      final double lean = -math.pi / 5 + spread * (angle + math.pi / 2);

      canvas
        ..save()
        ..translate(
          centre.dx + radius * math.cos(angle),
          centre.dy + radius * math.sin(angle),
        )
        ..rotate(lean + (1 - spread) * spin)
        ..scale(scale);
      paint.color = Color.lerp(leaf, trail, spread * share)!;
      rib.strokeWidth = 0.05;
      canvas
        ..drawPath(_leaf, paint)
        ..drawLine(const Offset(0, 0.42), const Offset(0, -0.3), rib)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_WhirlPainter old) =>
      old.leaf != leaf || old.trail != trail || old.vein != vein;
}
