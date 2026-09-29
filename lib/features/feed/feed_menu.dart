import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/feed/feed_model.dart';
import 'package:sielto/features/incomes/income_form_page.dart';
import 'package:sielto/features/payments/payment_form_page.dart';
import 'package:sielto/features/settings/holidays_page.dart';

enum _QuickAdd { payment, income, nonWorkingDay }

/// Fixed item height and menu padding, for [quickAddAnchor].
@visibleForTesting
const double quickAddItemHeight = kMinInteractiveDimension;
const double _menuVerticalPadding = 16;

/// The FAB menu: a bubble beside the button.
Future<void> showQuickAddMenu(
  BuildContext context,
  WidgetRef ref, {
  required CalendarDate today,
  required GlobalKey anchorKey,
}) async {
  final List<PopupMenuEntry<_QuickAdd>> items = _quickAddItems(ref);
  HapticFeedback.lightImpact();
  final _QuickAdd? choice = await showMenu<_QuickAdd>(
    context: context,
    position: quickAddAnchor(context, anchorKey, itemCount: items.length),
    color: context.sage.card,
    // Opens from the button, fast.
    popUpAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 140),
      reverseDuration: Duration(milliseconds: 100),
      curve: Curves.easeOutCubic,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(SageRadius.card),
    ),
    items: items,
  );
  if (choice == null || !context.mounted) return;
  HapticFeedback.lightImpact();

  switch (choice) {
    case _QuickAdd.payment:
      await openPaymentForm(context, date: today);
    case _QuickAdd.income:
      await openIncomeForm(context, date: today);
    case _QuickAdd.nonWorkingDay:
      await markNonWorkingDay(context, ref, initial: today);
  }
}

/// Built once so [quickAddAnchor] can count them.
List<PopupMenuEntry<_QuickAdd>> _quickAddItems(WidgetRef ref) =>
    <PopupMenuEntry<_QuickAdd>>[
      PopupMenuItem<_QuickAdd>(
        value: _QuickAdd.payment,
        height: quickAddItemHeight,
        child: _MenuLine(
          icon: Icons.remove_circle_outline,
          label: tr('payment.add'),
        ),
      ),
      PopupMenuItem<_QuickAdd>(
        value: _QuickAdd.income,
        height: quickAddItemHeight,
        child: _MenuLine(
          icon: Icons.add_circle_outline,
          // In Budget mode an income is a top-up of the fund.
          label: ref.space.budgetMode == BudgetMode.budget
              ? tr('budget.topUp')
              : tr('income.add'),
        ),
      ),
      PopupMenuItem<_QuickAdd>(
        value: _QuickAdd.nonWorkingDay,
        height: quickAddItemHeight,
        child: _MenuLine(
          icon: Icons.event_busy_outlined,
          label: tr('holidays.markDay'),
        ),
      ),
    ];

/// Where the bubble opens. `showMenu` places the top at `position.top` and
/// ignores `position.bottom`, so the top is computed from the item count.
@visibleForTesting
RelativeRect quickAddAnchor(
  BuildContext context,
  GlobalKey anchorKey, {
  required int itemCount,
}) {
  final RenderBox overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  final RenderBox? box =
      anchorKey.currentContext?.findRenderObject() as RenderBox?;
  if (box == null) return RelativeRect.fill;

  final Offset topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final Offset bottomRight = box.localToGlobal(
    box.size.bottomRight(Offset.zero),
    ancestor: overlay,
  );
  final double menuHeight =
      itemCount * quickAddItemHeight + _menuVerticalPadding;

  return RelativeRect.fromLTRB(
    topLeft.dx,
    topLeft.dy - menuHeight - SageSpace.sm,
    overlay.size.width - bottomRight.dx,
    overlay.size.height - bottomRight.dy,
  );
}

/// Icon and label.
class _MenuLine extends StatelessWidget {
  const _MenuLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Icon(icon, size: 20, color: context.sage.inkSecondary),
      const SizedBox(width: SageSpace.md),
      Text(label, style: Theme.of(context).textTheme.bodyLarge),
    ],
  );
}

/// Long-press menu on a row. Every item only prefills a date.
Future<void> showRecordMenu(
  BuildContext context,
  WidgetRef ref, {
  required FeedRecord record,
  required CalendarDate today,
}) => showModalBottomSheet<void>(
  context: context,
  builder: (BuildContext sheetContext) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SageSpace.gutter,
            SageSpace.md,
            SageSpace.gutter,
            SageSpace.sm,
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              record.title,
              style: Theme.of(sheetContext).textTheme.titleSmall,
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.arrow_upward),
          title: Text(tr('feed.addBefore')),
          onTap: () {
            Navigator.of(sheetContext).pop();
            _addOn(context, record, record.date.addDays(-1));
          },
        ),
        ListTile(
          leading: const Icon(Icons.arrow_downward),
          title: Text(tr('feed.addAfter')),
          onTap: () {
            Navigator.of(sheetContext).pop();
            _addOn(context, record, record.date.addDays(1));
          },
        ),
        if (!record.isIncome) ...<Widget>[
          ListTile(
            leading: const Icon(Icons.content_copy_outlined),
            title: Text(tr('feed.duplicateBefore')),
            onTap: () {
              Navigator.of(sheetContext).pop();
              _duplicate(context, ref, record, record.date.addDays(-1));
            },
          ),
          ListTile(
            leading: const Icon(Icons.content_copy),
            title: Text(tr('feed.duplicateAfter')),
            onTap: () {
              Navigator.of(sheetContext).pop();
              _duplicate(context, ref, record, record.date.addDays(1));
            },
          ),
        ],
      ],
    ),
  ),
);

/// Empty form on the neighbouring day.
void _addOn(BuildContext context, FeedRecord record, CalendarDate date) {
  if (record.isIncome) {
    openIncomeForm(context, date: date);
    return;
  }
  openPaymentForm(context, date: date);
}

/// Unsaved copy on the neighbouring day.
Future<void> _duplicate(
  BuildContext context,
  WidgetRef ref,
  FeedRecord record,
  CalendarDate date,
) async {
  final Payment? source = await ref
      .read(repositoriesProvider)
      .payments
      .byId(record.id);
  if (source == null || !context.mounted) return;
  await openPaymentForm(
    context,
    date: date,
    draft: PaymentDraft.from(source, date),
  );
}
