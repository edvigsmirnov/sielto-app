import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/action_sheet.dart';

/// Rings the focused control after a key press, until the next click.
/// Text fields keep their own focused border.
class FocusRing extends StatefulWidget {
  const FocusRing({required this.child, super.key});

  final Widget child;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  Rect? _rect;
  bool _watching = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance
      ..addListener(_check)
      ..addHighlightModeListener(_onMode);
    keyboardDriven.addListener(_check);
  }

  @override
  void dispose() {
    FocusManager.instance
      ..removeListener(_check)
      ..removeHighlightModeListener(_onMode);
    keyboardDriven.removeListener(_check);
    super.dispose();
  }

  void _onMode(FocusHighlightMode _) => _check();

  Rect? _focused() {
    if (FocusManager.instance.highlightMode != FocusHighlightMode.traditional ||
        !keyboardDriven.value) {
      return null;
    }
    final FocusNode? node = FocusManager.instance.primaryFocus;
    final BuildContext? at = node?.context;
    if (node == null || node is FocusScopeNode || at == null) return null;
    if (at.findAncestorWidgetOfExactType<EditableText>() != null) return null;
    final Rect rect = node.rect;
    return rect.isFinite ? rect : null;
  }

  // Follows the control through scrolls and transitions, frame by frame.
  void _check() {
    if (!mounted) return;
    final Rect? rect = _focused();
    if (rect != _rect) setState(() => _rect = rect);
    if (rect != null && !_watching) {
      _watching = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _watching = false;
        _check();
      });
    }
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _RingPainter(_rect, context.sage.accent),
    child: widget.child,
  );
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.rect, this.color);

  final Rect? rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect? r = rect;
    if (r == null) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        r.inflate(3).intersect((Offset.zero & size).deflate(2)),
        const Radius.circular(12),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.rect != rect || old.color != color;
}
