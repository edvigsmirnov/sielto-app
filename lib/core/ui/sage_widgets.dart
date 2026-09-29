import 'dart:ui' show PathMetric;

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/domain/ledger/ledger_walker.dart';

/// Card with the standard inner gutter; look from `cardTheme`.
class SageCard extends StatelessWidget {
  const SageCard({
    required this.child,
    this.padding = const EdgeInsets.all(SageSpace.gutter),
    this.onTap,
    this.selected = false,
    this.color,
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  final bool selected;

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final Widget body = Padding(padding: padding, child: child);
    return Card(
      color: color ?? (selected ? sage.accentTint : sage.card),
      child: onTap == null
          ? body
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(SageRadius.card),
              child: body,
            ),
    );
  }
}

/// Uppercase label above a form field.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: SageSpace.sm),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall,
    ),
  );
}

class LabelledField extends StatelessWidget {
  const LabelledField({required this.label, required this.child, super.key});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[FieldLabel(label), child],
  );
}

/// One choice from a short list, as segments.
class SegmentedChoice<T> extends StatelessWidget {
  const SegmentedChoice({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  /// Disabled still shows the selected value.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return Container(
      decoration: BoxDecoration(
        color: sage.card,
        borderRadius: BorderRadius.circular(SageRadius.input),
        border: Border.all(color: sage.border),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: <Widget>[
          for (final T value in values)
            Expanded(
              child: _Segment<T>(
                label: labelOf(value),
                isSelected: value == selected,
                onTap: enabled ? () => onChanged(value) : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment<T> extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SageRadius.chip),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? sage.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(SageRadius.chip),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: isSelected ? sage.accentOn : sage.inkSecondary),
        ),
      ),
    );
  }
}

/// Coverage: green spare, orange exact, red short.
class CoverageDot extends StatelessWidget {
  const CoverageDot(this.coverage, {this.size = 10, super.key});

  final Coverage coverage;
  final double size;

  /// Neutral when [coverage] is null.
  static Color colorOf(BuildContext context, Coverage? coverage) =>
      switch (coverage) {
        Coverage.covered => context.sage.accentStrong,
        Coverage.exact => context.sage.warningAccent,
        Coverage.short => context.sage.danger,
        null => context.sage.ink,
      };

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: colorOf(context, coverage),
      shape: BoxShape.circle,
    ),
  );
}

/// 1px row divider.
class Hairline extends StatelessWidget {
  const Hairline({this.indent = 0, super.key});

  final double indent;

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: 1,
    indent: indent,
    color: context.sage.hairline,
  );
}

class StatColumn extends StatelessWidget {
  const StatColumn({
    required this.label,
    required this.value,
    this.valueColor,
    super.key,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: text.labelMedium),
        const SizedBox(height: SageSpace.xs),
        Text(
          value,
          style: text.titleSmall?.copyWith(
            color: valueColor,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Icon on a soft square, for secondary actions.
class SoftIconButton extends StatelessWidget {
  const SoftIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 36,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SageRadius.button),
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sage.canvas,
            borderRadius: BorderRadius.circular(SageRadius.button),
            border: Border.all(color: sage.border),
          ),
          child: Icon(icon, size: size / 2, color: sage.inkSecondary),
        ),
      ),
    );
  }
}

/// Dashed outline button for adding an item.
class DashedButton extends StatelessWidget {
  const DashedButton({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SageRadius.card),
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: sage.border,
          radius: SageRadius.card,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: sage.inkSecondary),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final Path path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );

    const double dash = 6;
    const double gap = 4;
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
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

/// Label left, value right.
class StatRow extends StatelessWidget {
  const StatRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.emphasised = false,
    super.key,
  });

  final String label;
  final String value;
  final Color? valueColor;

  /// Value at title weight.
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SageSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(
                color: context.sage.inkSecondary,
              ),
            ),
          ),
          const SizedBox(width: SageSpace.md),
          Text(
            value,
            style: (emphasised ? text.titleMedium : text.bodyLarge)?.copyWith(
              color: valueColor ?? context.sage.ink,
              fontWeight: FontWeight.w700,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Animates between values. Frames are doubles; endpoints stay [Decimal].
class AnimatedMoney extends StatelessWidget {
  const AnimatedMoney({
    required this.value,
    required this.format,
    this.style,
    this.duration = const Duration(milliseconds: 300),
    super.key,
  });

  final Decimal value;
  final String Function(Decimal value) format;
  final TextStyle? style;
  final Duration duration;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween<double>(end: value.toDouble()),
    duration: duration,
    curve: Curves.easeOutCubic,
    builder: (BuildContext context, double frame, Widget? _) => Text(
      format(Decimal.parse(frame.toStringAsFixed(2))),
      style: (style ?? Theme.of(context).textTheme.titleSmall)?.copyWith(
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    ),
  );
}

/// Empty-state message with an optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({required this.message, this.action, super.key});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(SageSpace.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (action != null) ...<Widget>[
            const SizedBox(height: SageSpace.lg),
            action!,
          ],
        ],
      ),
    ),
  );
}
