import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/settings/local_settings.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/form_fields.dart';
import 'package:sielto/core/ui/layout.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/categories/category_colors.dart';
import 'package:sielto/features/categories/category_title.dart';
import 'package:sielto/features/feed/feed_columns.dart';
import 'package:sielto/features/feed/feed_model.dart';
import 'package:sielto/features/sync/refused_mark.dart';

/// How much the Feed's fixed extents grow with the reader's text size.
double feedGrowth(BuildContext context) =>
    math.max(1, MediaQuery.textScalerOf(context).scale(14) / 14);

/// Minimum row height per density.
double rowHeightFor(BuildContext context, FeedDensity density) =>
    feedGrowth(context) *
    switch (density) {
      FeedDensity.compact => 48,
      FeedDensity.standard => 72,
      FeedDensity.spacious => 100,
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
    this.onSecondaryTap,
    this.table,
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

  /// Right-click; the long press when null.
  final VoidCallback? onSecondaryTap;

  /// The wide layout's table columns; null for the narrow row.
  final FeedTableCells? table;

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

    final Widget row = _spoken(context, _row(context, amountColor));
    if (isBeyondDeadline) return Opacity(opacity: 0.45, child: row);
    return row;
  }

  /// One announcement for the row. The paid circle, the note and the refused
  /// mark stay buttons of their own.
  Widget _spoken(BuildContext context, Widget row) => Semantics(
    label: <String>[
      record.title,
      _amountLabel(record, money),
      if (record.isIncome)
        tr(record.isPaid ? 'income.received' : 'income.expected')
      else
        tr(record.isPaid ? 'payment.paid' : 'payment.unpaid'),
      if (record.expenseType == ExpenseType.mandatory) tr('payment.mandatory'),
      if (category case final Category c) c.shownTitle,
      if (isOverdue) tr('payment.overdue'),
      if (!record.isIncome && !isCovered && !record.isPaid)
        tr('coverage.short'),
      if (isFrozen) tr('freeze.frozenTitle'),
    ].join('. '),
    selected: isSelected,
    button: true,
    child: row,
  );

  Widget _row(BuildContext context, Color amountColor) {
    final SageColors sage = context.sage;

    return Dismissible(
      key: ValueKey<String>('dismiss:${record.id}'),
      // Right deletes, left toggles paid.
      direction: isFrozen || selecting || desktopInput
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
      // Its own Material, so the tint clips with the list.
      child: Material(
        type: MaterialType.transparency,
        child: Ink(
          decoration: BoxDecoration(
            color: isSelected
                ? sage.accentTint
                : (isOverdue ? sage.dangerTint : Colors.transparent),
            border: density == FeedDensity.spacious || table != null
                ? Border(bottom: BorderSide(color: sage.hairline, width: 0.5))
                : null,
          ),
          child: ConstrainedBox(
            // A minimum: the spacious subtitle can be taller.
            constraints: BoxConstraints(
              minHeight: rowHeightFor(context, density),
            ),
            child: Row(
              children: <Widget>[
                // The grip is outside the tappable area, so long-press does not compete with
                // it.
                Expanded(
                  child: CallbackShortcuts(
                    bindings: <ShortcutActivator, VoidCallback>{
                      if (!selecting &&
                          !isFrozen) ...<ShortcutActivator, VoidCallback>{
                        const SingleActivator(LogicalKeyboardKey.delete):
                            onDelete,
                        const SingleActivator(LogicalKeyboardKey.space):
                            onTogglePaid,
                      },
                    },
                    child: InkWell(
                      onTap: onTap,
                      onSecondaryTap: onSecondaryTap ?? onLongPress,
                      onLongPress: () {
                        HapticFeedback.mediumImpact();
                        onLongPress();
                      },
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          SageSpace.gutter - _leadInset,
                          density == FeedDensity.compact ? 4 : SageSpace.sm,
                          dragHandle == null ? SageSpace.gutter : SageSpace.xs,
                          density == FeedDensity.compact ? 4 : SageSpace.sm,
                        ),
                        child: Row(
                          children: <Widget>[
                            if (selecting)
                              SizedBox.square(
                                dimension: kMinInteractiveDimension,
                                child: Icon(
                                  isSelected
                                      ? Icons.check_box
                                      : Icons.check_box_outline_blank,
                                  size: 24,
                                  color: isSelected
                                      ? sage.accentStrong
                                      : sage.inkLabel,
                                ),
                              )
                            else
                              _PaidCircle(
                                record: record,
                                onTap: isFrozen ? null : onTogglePaid,
                              ),
                            const SizedBox(width: SageSpace.md - _leadInset),
                            if (table == null) ...<Widget>[
                              _TypeMarker(record: record, category: category),
                              const SizedBox(width: SageSpace.md),
                            ],
                            if (isOverdue && table == null) ...<Widget>[
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 16,
                                color: sage.danger,
                              ),
                              const SizedBox(width: SageSpace.xs),
                            ],
                            Expanded(
                              child: switch (table) {
                                final FeedTableCells cells => _TableCells(
                                  record: record,
                                  isOverdue: isOverdue,
                                  category: category,
                                  cells: cells,
                                  amount: _amountLabel(record, money),
                                  amountColor: amountColor,
                                ),
                                null => _RowBody(
                                  record: record,
                                  category: category,
                                  density: density,
                                  amount: _amountLabel(record, money),
                                  amountColor: amountColor,
                                  isFrozen: isFrozen,
                                ),
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                ?dragHandle,
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The 48 dp circle box reaches this far past the 26 dp circle.
  static const double _leadInset = (kMinInteractiveDimension - 26) / 2;

  String _amountLabel(FeedRecord r, MoneyFormat money) {
    if (r.amount == null) return tr('income.amountUnknown');
    return r.isIncome ? '+${money.format(r.amount!)}' : money.format(r.amount!);
  }
}

/// What a table row shows beyond the narrow row.
class FeedTableCells {
  const FeedTableCells({
    required this.date,
    required this.leftAfter,
    required this.short,
    required this.layout,
  });

  final String date;

  /// Left to spend after this entry; null when not worked out.
  final String? leftAfter;
  final bool short;
  final FeedColumnLayout layout;
}

/// Space the table keeps before and after its columns.
abstract final class FeedColumns {
  /// The paid circle and its gaps.
  static const double lead =
      SageSpace.gutter -
      FeedRowTile._leadInset +
      kMinInteractiveDimension +
      SageSpace.md -
      FeedRowTile._leadInset;

  /// The drag grip.
  static const double trail = 48;
}

/// Column headings above the table. Their edges drag to resize; a right-click
/// hides or shows columns.
class FeedTableHeader extends ConsumerWidget {
  const FeedTableHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SageColors sage = context.sage;
    final FeedColumnLayout layout = ref.watch(feedColumnsProvider);
    final FeedColumnsController columns = ref.read(
      feedColumnsProvider.notifier,
    );
    final TextStyle? style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: sage.inkLabel, fontWeight: FontWeight.w700);
    Text label(String key) => Text(
      tr('feed.table.$key').toUpperCase(),
      style: style,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    Widget cell(FeedColumn c) {
      final Widget edge = MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (DragUpdateDetails d) => columns.resize(
            c,
            layout.widthOf(c) + (c.dragsLeftEdge ? -d.delta.dx : d.delta.dx),
          ),
          onHorizontalDragEnd: (DragEndDetails _) => columns.save(),
          child: const SizedBox(width: 12, height: double.infinity),
        ),
      );
      return SizedBox(
        width: layout.widthOf(c),
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(child: label(c.name)),
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              left: c.dragsLeftEdge ? 0 : null,
              right: c.dragsLeftEdge ? null : 0,
              child: edge,
            ),
          ],
        ),
      );
    }

    final List<FeedColumn> shown = layout.shown;
    return ExcludeSemantics(
      child: GestureDetector(
        onSecondaryTapUp: (TapUpDetails d) =>
            _menu(context, d.globalPosition, layout, columns),
        child: Container(
          height: 32,
          padding: const EdgeInsets.only(
            left: FeedColumns.lead,
            right: FeedColumns.trail,
          ),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: sage.hairline)),
          ),
          child: Row(
            children: <Widget>[
              for (final FeedColumn c in shown)
                if (c == FeedColumn.date) cell(c),
              Expanded(child: label('title')),
              for (final FeedColumn c in shown)
                if (c != FeedColumn.date) cell(c),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _menu(
    BuildContext context,
    Offset at,
    FeedColumnLayout layout,
    FeedColumnsController columns,
  ) async {
    final Object? picked = await showMenu<Object>(
      context: context,
      popUpAnimationStyle: AnimationStyle.noAnimation,
      // The position is global; a column's own navigator is offset.
      useRootNavigator: true,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: <PopupMenuEntry<Object>>[
        for (final FeedColumn c in FeedColumn.values)
          CheckedPopupMenuItem<Object>(
            value: c,
            checked: !layout.hidden.contains(c),
            child: Text(tr('feed.table.${c.name}')),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<Object>(
          value: #reset,
          child: Text(tr('feed.table.reset')),
        ),
      ],
    );
    if (picked is FeedColumn) await columns.toggle(picked);
    if (picked == #reset) await columns.reset();
  }
}

class _TableCells extends StatelessWidget {
  const _TableCells({
    required this.record,
    required this.isOverdue,
    required this.category,
    required this.cells,
    required this.amount,
    required this.amountColor,
  });

  final FeedRecord record;
  final bool isOverdue;
  final Category? category;
  final FeedTableCells cells;
  final String amount;
  final Color amountColor;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    final TextStyle muted = text.bodySmall!.copyWith(color: sage.inkSecondary);
    final TextStyle figures = text.bodyMedium!.copyWith(
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    final String? note = record.notes?.trim().isEmpty ?? true
        ? null
        : shownNote(context, record.notes!.trim());
    final FeedColumnLayout layout = cells.layout;
    Text line(String value, TextStyle style) => Text(
      value,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );
    Widget cell(FeedColumn c) {
      final Widget content = switch (c) {
        FeedColumn.date => line(cells.date, muted),
        FeedColumn.category => line(category?.shownTitle ?? '', muted),
        FeedColumn.kind => line(
          tr(
            'feed.filter.kind.${record.isIncome
                ? 'income'
                : record.isMandatory
                ? 'mandatory'
                : 'variable'}',
          ),
          muted,
        ),
        FeedColumn.note => line(note ?? '', muted),
        FeedColumn.amount => line(
          amount,
          figures.copyWith(color: amountColor, fontWeight: FontWeight.w700),
        ),
        FeedColumn.left => line(
          cells.leftAfter ?? '',
          figures.copyWith(
            color: cells.short ? sage.danger : sage.inkSecondary,
          ),
        ),
      };
      return SizedBox(
        width: layout.widthOf(c),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: content,
        ),
      );
    }

    final List<FeedColumn> shown = layout.shown;
    return Row(
      children: <Widget>[
        for (final FeedColumn c in shown)
          if (c == FeedColumn.date) cell(c),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (isOverdue) ...<Widget>[
                Icon(Icons.warning_amber_rounded, size: 16, color: sage.danger),
                const SizedBox(width: SageSpace.xs),
              ],
              Flexible(
                child: line(
                  record.title,
                  text.bodyLarge!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: record.isPaid ? sage.inkSecondary : sage.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (final FeedColumn c in shown)
          if (c != FeedColumn.date) cell(c),
      ],
    );
  }
}

/// Title and amount on one line when both fit, else the amount below. Then
/// the category from standard up, and the note's start in spacious.
class _RowBody extends StatelessWidget {
  const _RowBody({
    required this.record,
    required this.category,
    required this.density,
    required this.amount,
    required this.amountColor,
    required this.isFrozen,
  });

  final FeedRecord record;
  final Category? category;
  final FeedDensity density;
  final String amount;
  final Color amountColor;
  final bool isFrozen;

  /// Wider amounts go under the title.
  static const double _amountShare = 0.4;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    final String? note = record.notes?.trim().isEmpty ?? true
        ? null
        : shownNote(context, record.notes!.trim());
    final bool spacious = density == FeedDensity.spacious;

    final TextStyle titleStyle = text.bodyLarge!.copyWith(
      fontWeight: FontWeight.w600,
      color: record.isPaid ? sage.inkSecondary : sage.ink,
    );
    final TextStyle amountStyle = text.bodyLarge!.copyWith(
      color: amountColor,
      fontWeight: FontWeight.w600,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );

    final List<Widget> marks = <Widget>[
      if (record.refused) RefusedMark(record),
      if (isFrozen)
        Padding(
          padding: const EdgeInsets.only(left: SageSpace.sm),
          child: Icon(Icons.lock_outline, size: 16, color: sage.inkLabel),
        ),
      if (note != null && !spacious)
        Semantics(
          label: tr('feed.a11y.showNote'),
          button: true,
          excludeSemantics: true,
          onTap: () => _showNote(context, note),
          child: InkWell(
            onTap: () => _showNote(context, note),
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Icon(
                Icons.sticky_note_2_outlined,
                size: 18,
                color: sage.inkLabel,
              ),
            ),
          ),
        ),
    ];
    final double marksWidth =
        (record.refused ? 48 : 0) +
        (isFrozen ? 24 : 0) +
        (note != null && !spacious ? 48 : 0);

    // The row's own label says all of this.
    final Widget title = ExcludeSemantics(
      child: Text(
        record.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: titleStyle,
      ),
    );
    final Widget amountText = ExcludeSemantics(
      child: Text(
        amount,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: amountStyle,
      ),
    );

    final Category? c = category;
    final Widget? meta = density == FeedDensity.compact || c == null
        ? null
        : ExcludeSemantics(
            child: Row(
              children: <Widget>[
                CategoryMark(color: c.color, icon: c.icon, size: 20),
                const SizedBox(width: SageSpace.xs),
                Flexible(
                  child: Text(
                    c.shownTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(color: sage.inkSecondary),
                  ),
                ),
              ],
            ),
          );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        double width(String value, TextStyle style) {
          final TextPainter painter = TextPainter(
            text: TextSpan(text: value, style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          final double w = painter.width;
          painter.dispose();
          return w;
        }

        final double titleWidth = width(record.title, titleStyle);
        final double amountWidth = width(amount, amountStyle);
        final double room = constraints.maxWidth - marksWidth - SageSpace.sm;
        final bool oneLine =
            titleWidth + amountWidth <= room ||
            amountWidth <= constraints.maxWidth * _amountShare;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (oneLine)
              Row(
                children: <Widget>[
                  Expanded(child: title),
                  ...marks,
                  const SizedBox(width: SageSpace.sm),
                  amountText,
                ],
              )
            else ...<Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: title),
                  ...marks,
                ],
              ),
              Align(alignment: Alignment.centerRight, child: amountText),
            ],
            if (meta != null)
              Padding(padding: const EdgeInsets.only(top: 2), child: meta),
            if (spacious && note != null)
              Semantics(
                label: tr('feed.a11y.showNote'),
                button: true,
                excludeSemantics: true,
                onTap: () => _showNote(context, note),
                child: InkWell(
                  onTap: () => _showNote(context, note),
                  child: Container(
                    constraints: const BoxConstraints(
                      minHeight: kMinInteractiveDimension,
                    ),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.sticky_note_2_outlined,
                            size: 14,
                            color: sage.inkLabel,
                          ),
                        ),
                        const SizedBox(width: SageSpace.xs),
                        Expanded(
                          child: Text(
                            note,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The whole note.
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
    return Semantics(
      button: widget.onTap != null,
      label: tr(
        'feed.bulk.${paid ? 'unmark' : 'mark'}.'
        '${widget.record.isIncome ? 'received' : 'paid'}',
      ),
      excludeSemantics: true,
      onTap: widget.onTap,
      child: InkWell(
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.lightImpact();
                widget.onTap!();
              },
        customBorder: const CircleBorder(),
        child: SizedBox.square(
          dimension: kMinInteractiveDimension,
          child: Center(
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
                    child: Icon(
                      Icons.check,
                      size: 15,
                      color: paid ? sage.accentOn : sage.border,
                    ),
                  ),
                ),
              ),
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
        color: solid ? color : color.withValues(alpha: 0.35),
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
