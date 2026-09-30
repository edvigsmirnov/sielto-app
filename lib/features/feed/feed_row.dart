import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/settings/local_settings.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/features/categories/category_colors.dart';
import 'package:sielto/features/categories/category_title.dart';
import 'package:sielto/features/feed/feed_model.dart';

/// Row detail per density.
enum RowDetail {
  /// Title and amount.
  titleOnly,

  /// Plus paid or unpaid, expected or received.
  status,

  /// Plus the category.
  categoryAndStatus,
}

RowDetail detailFor(FeedDensity density) => switch (density) {
  FeedDensity.compact => RowDetail.titleOnly,
  FeedDensity.standard => RowDetail.status,
  FeedDensity.spacious => RowDetail.categoryAndStatus,
};

/// Minimum row height per density.
double rowHeightFor(FeedDensity density) => switch (density) {
  FeedDensity.compact => 48,
  FeedDensity.standard => 72,
  FeedDensity.spacious => 96,
};

/// Frozen rows keep only tap and long-press.
class FeedRowTile extends StatelessWidget {
  const FeedRowTile({
    required this.record,
    required this.isCovered,
    required this.density,
    required this.money,
    required this.category,
    required this.onTap,
    required this.onTogglePaid,
    required this.onDelete,
    required this.onLongPress,
    this.isFrozen = false,
    this.isOverdue = false,
    this.isBeyondDeadline = false,
    this.dragHandle,
    this.selecting = false,
    this.isSelected = false,
    super.key,
  });

  final FeedRecord record;
  final bool isCovered;
  final FeedDensity density;
  final MoneyFormat money;

  /// Null without a category, and for incomes.
  final Category? category;

  final VoidCallback onTap;
  final VoidCallback onTogglePaid;
  final VoidCallback onDelete;
  final VoidCallback onLongPress;

  final bool isFrozen;

  final bool isOverdue;

  /// Dimmed and excluded.
  final bool isBeyondDeadline;

  final Widget? dragHandle;

  /// While any row is selected, a tap selects and swipes are off.
  final bool selecting;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    // Incomes green; expenses red when uncovered or overdue.
    final Color amountColor = record.isIncome
        ? sage.accentStrong
        : (isOverdue || !isCovered ? sage.danger : sage.ink);

    if (isBeyondDeadline) {
      return Opacity(opacity: 0.45, child: _row(context, amountColor));
    }
    return _row(context, amountColor);
  }

  Widget _row(BuildContext context, Color amountColor) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;

    return Dismissible(
      key: ValueKey<String>('dismiss:${record.id}'),
      // Right deletes, left toggles paid.
      direction: isFrozen || selecting
          ? DismissDirection.none
          : DismissDirection.horizontal,
      background: const _SwipeAction(
        alignment: Alignment.centerLeft,
        icon: Icons.delete_outline,
        labelKey: 'common.delete',
        isDestructive: true,
      ),
      secondaryBackground: _SwipeAction(
        alignment: Alignment.centerRight,
        icon: Icons.check_circle_outline,
        labelKey: record.isIncome ? 'income.received' : 'payment.togglePaid',
        isDestructive: false,
      ),
      confirmDismiss: (DismissDirection direction) async {
        HapticFeedback.mediumImpact();
        if (direction == DismissDirection.startToEnd) {
          onDelete();
        } else {
          onTogglePaid();
        }
        // The query removes the row, so an undo brings it back.
        return false;
      },
      child: Ink(
        color: isSelected
            ? sage.accentTint
            : (isOverdue ? sage.dangerTint : Colors.transparent),
        child: ConstrainedBox(
          // A minimum: the spacious subtitle can be taller.
          constraints: BoxConstraints(minHeight: rowHeightFor(density)),
          child: Row(
            children: <Widget>[
              // The grip is outside the tappable area, so long-press does not compete with
              // it.
              Expanded(
                child: InkWell(
                  onTap: onTap,
                  onLongPress: () {
                    HapticFeedback.mediumImpact();
                    onLongPress();
                  },
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      SageSpace.gutter,
                      density == FeedDensity.compact ? 4 : SageSpace.sm,
                      dragHandle == null ? SageSpace.gutter : SageSpace.xs,
                      density == FeedDensity.compact ? 4 : SageSpace.sm,
                    ),
                    child: Row(
                      children: <Widget>[
                        _PaidCircle(
                          record: record,
                          onTap: isFrozen || selecting ? null : onTogglePaid,
                        ),
                        const SizedBox(width: SageSpace.md),
                        _TypeMarker(record: record, category: category),
                        const SizedBox(width: SageSpace.md),
                        if (isOverdue) ...<Widget>[
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: sage.danger,
                          ),
                          const SizedBox(width: SageSpace.xs),
                        ],
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                record.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: record.isPaid
                                      ? sage.inkSecondary
                                      : sage.ink,
                                  decoration: record.isPaid
                                      ? TextDecoration.lineThrough
                                      : null,
                                  decorationColor: sage.inkLabel.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                              if (_subtitle(record, category)
                                  case final String sub)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    sub,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodySmall,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (isFrozen)
                          Padding(
                            padding: const EdgeInsets.only(left: SageSpace.sm),
                            child: Icon(
                              Icons.lock_outline,
                              size: 16,
                              color: sage.inkLabel,
                            ),
                          ),
                        if (record.notes != null && record.notes!.isNotEmpty)
                          InkWell(
                            onTap: () => _showNote(context, record.notes!),
                            customBorder: const CircleBorder(),
                            child: Padding(
                              padding: const EdgeInsets.all(SageSpace.xs),
                              child: Icon(
                                Icons.sticky_note_2_outlined,
                                size: 18,
                                color: sage.inkLabel,
                              ),
                            ),
                          ),
                        const SizedBox(width: SageSpace.sm),
                        Text(
                          _amountLabel(record, money),
                          style: text.bodyLarge?.copyWith(
                            color: amountColor,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              ?dragHandle,
            ],
          ),
        ),
      ),
    );
  }

  String _amountLabel(FeedRecord r, MoneyFormat money) {
    if (r.amount == null) return tr('income.amountUnknown');
    return r.isIncome ? '+${money.format(r.amount!)}' : money.format(r.amount!);
  }

  /// Null for compact rows.
  String? _subtitle(FeedRecord r, Category? category) {
    final RowDetail detail = detailFor(density);
    if (detail == RowDetail.titleOnly) return null;

    final String status = r.isIncome
        ? (r.isPaid ? tr('income.received') : tr('income.expected'))
        : (r.isPaid ? tr('payment.paid') : tr('payment.unpaid'));

    if (detail == RowDetail.status || category == null) return status;
    return '${category.shownTitle} · $status';
  }

  void _showNote(BuildContext context, String note) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: context.sage.card,
        content: Text(note, style: Theme.of(context).textTheme.bodyLarge),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('common.close')),
          ),
        ],
      ),
    );
  }
}

/// Filled once paid. Becoming paid sends short rays out of it.
class _PaidCircle extends StatefulWidget {
  const _PaidCircle({required this.record, required this.onTap});

  final FeedRecord record;

  /// Null when frozen.
  final VoidCallback? onTap;

  @override
  State<_PaidCircle> createState() => _PaidCircleState();
}

class _PaidCircleState extends State<_PaidCircle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rays = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void didUpdateWidget(_PaidCircle old) {
    super.didUpdateWidget(old);
    if (widget.record.isPaid &&
        !old.record.isPaid &&
        !MediaQuery.disableAnimationsOf(context)) {
      _rays.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _rays.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final bool paid = widget.record.isPaid;
    return GestureDetector(
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              widget.onTap!();
            },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 26,
        height: 26,
        child: CustomPaint(
          foregroundPainter: _RaysPainter(
            progress: _rays,
            color: sage.accentStrong,
          ),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: paid ? sage.accent : Colors.transparent,
                border: Border.all(
                  color: paid ? sage.accent : sage.border,
                  width: 1.5,
                ),
              ),
              child: paid
                  ? Icon(Icons.check, size: 15, color: sage.accentOn)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Eight thin strokes that travel outward and fade.
class _RaysPainter extends CustomPainter {
  _RaysPainter({required this.progress, required this.color})
    : super(repaint: progress);

  final Animation<double> progress;
  final Color color;

  static const int _count = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final double t = progress.value;
    if (t == 0 || t == 1) return;
    final double eased = Curves.easeOutCubic.transform(t);
    final Offset centre = size.center(Offset.zero);
    final double inner = 12 + 6 * eased;
    final double outer = inner + 5 * (1 - t);
    final Paint paint = Paint()
      ..color = color.withValues(alpha: 0.7 * (1 - t))
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < _count; i++) {
      final double angle = i * 2 * math.pi / _count;
      final Offset dir = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(centre + dir * inner, centre + dir * outer, paint);
    }
  }

  @override
  bool shouldRepaint(_RaysPainter old) =>
      old.progress != progress || old.color != color;
}

/// Solid for mandatory, hollow for variable, in the category colour. Incomes
/// use the accent.
class _TypeMarker extends StatelessWidget {
  const _TypeMarker({required this.record, required this.category});

  final FeedRecord record;
  final Category? category;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final Color color = parseCategoryColor(category?.color) ?? sage.accent;
    final bool solid = record.isIncome || record.isMandatory;
    return Container(
      width: 3,
      height: 22,
      decoration: BoxDecoration(
        color: solid ? color : Colors.transparent,
        border: solid ? null : Border.all(color: color),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// Background shown while a row is swiped.
class _SwipeAction extends StatelessWidget {
  const _SwipeAction({
    required this.alignment,
    required this.icon,
    required this.labelKey,
    required this.isDestructive,
  });

  final Alignment alignment;
  final IconData icon;
  final String labelKey;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final Color tint = isDestructive ? sage.dangerTint : sage.accentTint;
    final Color ink = isDestructive ? sage.danger : sage.accentStrong;
    return Container(
      color: tint,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: SageSpace.lg),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 20, color: ink),
          const SizedBox(width: SageSpace.sm),
          Text(
            tr(labelKey),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: ink),
          ),
        ],
      ),
    );
  }
}
