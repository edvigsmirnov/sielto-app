import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';

/// The FAB while items are selected. Rings pulse around it while [pulse].
class BulkActionsButton extends StatefulWidget {
  const BulkActionsButton({
    required this.pulse,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final bool pulse;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<BulkActionsButton> createState() => _BulkActionsButtonState();
}

class _BulkActionsButtonState extends State<BulkActionsButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rings = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(BulkActionsButton old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final bool run = widget.pulse && !MediaQuery.disableAnimationsOf(context);
    if (run && !_rings.isAnimating) _rings.repeat();
    if (!run && _rings.isAnimating) _rings.reset();
  }

  @override
  void dispose() {
    _rings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return CustomPaint(
      painter: _RingsPainter(progress: _rings, color: sage.accent),
      child: FloatingActionButton(
        backgroundColor: sage.accent,
        foregroundColor: sage.accentOn,
        shape: const CircleBorder(),
        tooltip: widget.tooltip,
        onPressed: widget.onPressed,
        child: const Icon(Icons.more_horiz),
      ),
    );
  }
}

/// Two rings expanding from the button edge, half a cycle apart.
class _RingsPainter extends CustomPainter {
  _RingsPainter({required this.progress, required this.color})
    : super(repaint: progress);

  final Animation<double> progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress.value == 0) return;
    final Offset centre = size.center(Offset.zero);
    final double base = size.shortestSide / 2;
    for (final double shift in <double>[0, 0.5]) {
      final double t = (progress.value + shift) % 1;
      canvas.drawCircle(
        centre,
        base + 14 * Curves.easeOut.transform(t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: 0.35 * (1 - t)),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) =>
      old.progress != progress || old.color != color;
}
