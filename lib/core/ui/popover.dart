import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/action_sheet.dart';
import 'package:sielto/core/ui/layout.dart';

/// A card by [anchor], or by the last click for a large anchor.
Future<T?> showPopover<T>(
  BuildContext anchor, {
  required WidgetBuilder builder,
  double width = 360,
}) {
  final RenderBox box = anchor.findRenderObject()! as RenderBox;
  final Offset? click = lastPointer;
  final Rect at = box.size.height > 120 && click != null
      ? Rect.fromCenter(center: click, width: 1, height: 1)
      : box.localToGlobal(Offset.zero) & box.size;
  return showGeneralDialog<T>(
    context: anchor,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(anchor).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: MediaQuery.disableAnimationsOf(anchor)
        ? Duration.zero
        : const Duration(milliseconds: 120),
    transitionBuilder: (
      BuildContext _,
      Animation<double> animation,
      Animation<double> _,
      Widget child,
    ) => FadeTransition(opacity: animation, child: child),
    pageBuilder:
        (BuildContext context, Animation<double> _, Animation<double> _) =>
            CustomSingleChildLayout(
              delegate: _Placement(at),
              child: SizedBox(
                width: width,
                child: Material(
                  color: context.sage.card,
                  elevation: 6,
                  shadowColor: Colors.black26,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(SageRadius.card),
                    side: BorderSide(color: context.sage.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(SageSpace.gutter),
                    child: builder(context),
                  ),
                ),
              ),
            ),
  );
}

class _Placement extends SingleChildLayoutDelegate {
  const _Placement(this.anchor);

  final Rect anchor;

  static const double _margin = 16;
  static const double _gap = 4;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest)
          .deflate(const EdgeInsets.all(_margin));

  @override
  Offset getPositionForChild(Size size, Size child) {
    final double below = anchor.bottom + _gap;
    final double y = below + child.height <= size.height - _margin
        ? below
        : (anchor.top - _gap - child.height).clamp(_margin, double.infinity);
    final double x = (anchor.center.dx - child.width / 2).clamp(
      _margin,
      size.width - _margin - child.width,
    );
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_Placement old) => old.anchor != anchor;
}

/// A popover when wide, a bottom sheet otherwise.
Future<T?> showAdaptiveSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double width = 400,
}) => isWide(context)
    ? showPopover<T>(context, builder: builder, width: width)
    : showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        builder: builder,
      );
