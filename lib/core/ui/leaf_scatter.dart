import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:sielto/core/ui/leaf_loader.dart';

/// Captures [key]'s [RepaintBoundary] at device resolution. Null before first
/// paint.
Future<ui.Image?> snapshotOf(GlobalKey key) async {
  final BuildContext? context = key.currentContext;
  final RenderObject? box = context?.findRenderObject();
  if (context == null || box is! RenderRepaintBoundary || box.debugNeedsPaint) {
    return null;
  }
  return box.toImage(pixelRatio: View.of(context).devicePixelRatio);
}

/// Blows [image] away as leaves: right to left, or outwards from [origin].
/// Reduced motion: a short fade.
class LeafScatter extends StatefulWidget {
  const LeafScatter({
    required this.image,
    required this.onDone,
    this.origin,
    super.key,
  });

  final ui.Image image;
  final Offset? origin;
  final VoidCallback onDone;

  @override
  State<LeafScatter> createState() => _LeafScatterState();
}

class _LeafScatterState extends State<LeafScatter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addStatusListener((AnimationStatus s) {
      if (s.isCompleted) widget.onDone();
    });

  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.isCompleted) return;
    _reduced = MediaQuery.disableAnimationsOf(context);
    _controller
      ..duration = _reduced
          ? const Duration(milliseconds: 200)
          : Duration(milliseconds: (_ScatterPainter.total * 1000).round())
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double ratio = View.of(context).devicePixelRatio;
    if (_reduced) {
      return IgnorePointer(
        child: FadeTransition(
          opacity: ReverseAnimation(_controller),
          child: RawImage(image: widget.image, scale: ratio, fit: BoxFit.fill),
        ),
      );
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _ScatterPainter(
            progress: _controller,
            image: widget.image,
            ratio: ratio,
            origin: widget.origin,
          ),
        ),
      ),
    );
  }
}

class _Piece {
  _Piece({
    required this.cell,
    required this.leaf,
    required this.centre,
    required this.release,
    required this.life,
    required this.direction,
    required this.speed,
    required this.gust,
    required this.lift,
    required this.flutter,
    required this.flutterRate,
    required this.phase,
    required this.spin,
    required this.flipRate,
  });

  final Rect cell;
  final Path leaf;
  final Offset centre;

  /// Seconds from the start.
  final double release;

  /// Seconds in flight.
  final double life;

  final Offset direction;
  final double speed;
  final double gust;
  final double lift;
  final double flutter;
  final double flutterRate;
  final double phase;
  final double spin;
  final double flipRate;
}

class _ScatterPainter extends CustomPainter {
  _ScatterPainter({
    required this.progress,
    required this.image,
    required this.ratio,
    required this.origin,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final ui.Image image;
  final double ratio;
  final Offset? origin;

  /// Wave duration, extra random delay and maximum flight time, in seconds.
  static const double _wave = 0.5;
  static const double _stagger = 0.16;
  static const double _maxLife = 0.8;
  static const double total = _wave + _stagger + _maxLife;

  Size? _builtFor;
  List<_Piece> _pieces = const <_Piece>[];

  List<_Piece> _cut(Size size) {
    // Fixed seed: pieces stay the same across repaints.
    final math.Random random = math.Random(7);
    double between(double a, double b) => a + random.nextDouble() * (b - a);

    final double side = size.shortestSide / 9;
    final int cols = (size.width / side).ceil();
    final int rows = (size.height / side).ceil();
    final Offset? from = origin;
    final double reach = from == null
        ? size.width
        : <Offset>[
            Offset.zero,
            Offset(size.width, 0),
            Offset(0, size.height),
            Offset(size.width, size.height),
          ].map((Offset c) => (c - from).distance).reduce(math.max);
    final Path unit = leafPath();

    return <_Piece>[
      for (int r = 0; r < rows; r++)
        for (int c = 0; c < cols; c++)
          () {
            final Rect cell = Rect.fromLTWH(c * side, r * side, side, side);
            final Offset centre = cell.center;
            // Wave arrival, 0 to 1, with a wavy front.
            final double reached = from == null
                ? 1 -
                      centre.dx / size.width +
                      0.08 * math.sin(centre.dy / size.height * 7 + 1.3)
                : (centre - from).distance / reach;
            final Offset away = from == null
                ? Offset(-1, between(-0.45, 0.15))
                : () {
                    // Stretched sideways.
                    final Offset d = centre - from;
                    final Offset o = Offset(
                      d.dx * 1.8 + between(-40, 40),
                      d.dy - 24,
                    );
                    final double n = o.distance;
                    return n == 0 ? const Offset(0, -1) : o / n;
                  }();
            // Leaf longer than the cell so it covers most of it.
            final double length = side * between(1.7, 2.1);
            final Matrix4 place = Matrix4.identity()
              ..translateByDouble(centre.dx, centre.dy, 0, 1)
              ..rotateZ(between(-1.2, 1.2) + math.pi / 4)
              ..scaleByDouble(length, length, 1, 1);
            return _Piece(
              cell: cell,
              leaf: unit.transform(place.storage),
              centre: centre,
              release:
                  reached.clamp(0.0, 1.0) * _wave +
                  random.nextDouble() * _stagger,
              life: between(0.5, _maxLife),
              direction: away,
              speed: between(80, 260),
              gust: between(900, 1900),
              lift: between(-180, 420),
              flutter: between(6, 24),
              flutterRate: between(7, 13),
              phase: between(0, 2 * math.pi),
              spin: between(2.5, 8) * (random.nextBool() ? 1 : -1),
              flipRate: between(3, 9),
            );
          }(),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (_builtFor != size) {
      _pieces = _cut(size);
      _builtFor = size;
    }
    final double t = progress.value * total;
    final Paint paint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.low
      ..shader = ImageShader(
        image,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.diagonal3Values(1 / ratio, 1 / ratio, 1).storage,
      );

    // Cells not yet released.
    final Path still = Path();
    for (final _Piece p in _pieces) {
      if (t < p.release) still.addRect(p.cell);
    }
    canvas.drawPath(still, paint);

    for (final _Piece p in _pieces) {
      final double s = t - p.release;
      if (s < 0 || s > p.life) continue;
      final double k = s / p.life;

      final double along = p.speed * s + 0.5 * p.gust * s * s;
      final Offset side = Offset(-p.direction.dy, p.direction.dx);
      final Offset moved =
          p.direction * along +
          Offset(0, -0.5 * p.lift * s * s) +
          side * (p.flutter * math.sin(p.flutterRate * s + p.phase));
      final double turn = p.spin * s + 0.35 * math.sin(p.flutterRate * s);
      final double flip = math.cos(p.flipRate * s + p.phase);
      final double shrink = 1 - 0.3 * k;

      paint.color = Color.fromRGBO(
        0,
        0,
        0,
        (1 - Curves.easeIn.transform(((k - 0.3) / 0.7).clamp(0.0, 1.0))),
      );
      canvas
        ..save()
        ..translate(p.centre.dx + moved.dx, p.centre.dy + moved.dy)
        ..rotate(turn)
        ..scale(shrink * (0.35 + 0.65 * flip.abs()), shrink)
        ..translate(-p.centre.dx, -p.centre.dy)
        ..drawPath(p.leaf, paint)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_ScatterPainter old) =>
      old.image != image || old.origin != origin || old.ratio != ratio;
}
