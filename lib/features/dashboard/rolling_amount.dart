import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/features/sync/activity.dart';

/// An amount that rolls to its new value, with the difference floating above,
/// when another member's change moves it. Own edits change it at once.
class RollingAmount extends ConsumerStatefulWidget {
  const RollingAmount({
    required this.value,
    required this.money,
    this.style,
    super.key,
  });

  final Decimal value;
  final MoneyFormat money;
  final TextStyle? style;

  @override
  ConsumerState<RollingAmount> createState() => _RollingAmountState();
}

class _RollingAmountState extends ConsumerState<RollingAmount>
    with SingleTickerProviderStateMixin {
  static const Duration _roll = Duration(milliseconds: 700);
  static const Duration _hold = Duration(milliseconds: 3200);

  /// A change this long after a remote edit counts as that edit's.
  static const Duration _window = Duration(seconds: 5);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _roll,
  );
  late Decimal _from = widget.value;
  Decimal _delta = Decimal.zero;
  bool _showing = false;
  Timer? _hide;

  @override
  void dispose() {
    _hide?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(RollingAmount old) {
    super.didUpdateWidget(old);
    if (old.value == widget.value) return;
    final RemoteEdit? edit = ref.read(remoteEditProvider);
    final bool remote =
        edit != null &&
        edit.spaceId == ref.read(currentSpaceIdProvider) &&
        DateTime.now().difference(edit.at) < _window;
    if (!remote || MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      return;
    }
    _from = _shown(old.value);
    _delta = (_showing ? _delta : Decimal.zero) + widget.value - old.value;
    _showing = true;
    _controller.forward(from: 0);
    _hide?.cancel();
    _hide = Timer(_hold, () {
      if (mounted) setState(() => _showing = false);
    });
  }

  Decimal _shown(Decimal target) {
    if (!_controller.isAnimating) return target;
    final double t = Curves.easeOutCubic.transform(_controller.value);
    final double from = _from.toDouble();
    return Decimal.parse(
      (from + (target.toDouble() - from) * t).toStringAsFixed(2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: <Widget>[
        AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext _, Widget? _) => Text(
            widget.money.format(_shown(widget.value)),
            textAlign: TextAlign.center,
            style: widget.style,
          ),
        ),
        Positioned(
          right: 0,
          bottom: -SageSpace.lg,
          child: ExcludeSemantics(
            child: AnimatedOpacity(
              opacity: _showing ? 1 : 0,
              duration: const Duration(milliseconds: 400),
              child: AnimatedSlide(
                offset: _showing ? Offset.zero : const Offset(0, 0.6),
                duration: _roll,
                curve: Curves.easeOutCubic,
                child: Text(
                  widget.money.formatSigned(_delta),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: _delta < Decimal.zero ? sage.danger : sage.accent,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
