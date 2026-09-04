import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/incomes/income_form_page.dart';
import 'package:sielto/features/payments/payment_form_page.dart';
import 'package:sielto/features/settings/holidays_page.dart';

enum _DayAction { payment, income, nonWorkingDay }

/// The long-press menu on a calendar day (spec 8.1).
///
/// The same three actions as the Feed's quick-add menu and in the same order,
/// with one difference: here the date is the day that was held, so nothing is
/// asked twice — the form opens on that day and the non-working day is marked
/// on it directly.
Future<void> showDayMenu(
  BuildContext context,
  WidgetRef ref, {
  required CalendarDate date,
  required Offset at,
}) async {
  final RenderBox overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;

  final _DayAction? choice = await showMenu<_DayAction>(
    context: context,
    // Anchored on the finger. A day cell is small and there are forty-two of
    // them, so a menu placed relative to the grid would cover the day it is
    // about.
    position: RelativeRect.fromLTRB(
      at.dx,
      at.dy,
      overlay.size.width - at.dx,
      overlay.size.height - at.dy,
    ),
    color: context.sage.card,
    popUpAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 140),
      reverseDuration: Duration(milliseconds: 100),
      curve: Curves.easeOutCubic,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(SageRadius.card),
    ),
    items: <PopupMenuEntry<_DayAction>>[
      PopupMenuItem<_DayAction>(
        value: _DayAction.payment,
        child: _MenuLine(
          icon: Icons.remove_circle_outline,
          label: tr('payment.add'),
        ),
      ),
      PopupMenuItem<_DayAction>(
        value: _DayAction.income,
        child: _MenuLine(
          icon: Icons.add_circle_outline,
          // Same record, different meaning: in Budget mode money arriving is
          // not income for a period, it is a payment into the fund (spec 4.8).
          label: ref.space.budgetMode == BudgetMode.budget
              ? tr('budget.topUp')
              : tr('income.add'),
        ),
      ),
      PopupMenuItem<_DayAction>(
        value: _DayAction.nonWorkingDay,
        child: _MenuLine(
          icon: Icons.event_busy_outlined,
          label: tr('holidays.markDay'),
        ),
      ),
    ],
  );
  if (choice == null || !context.mounted) return;

  switch (choice) {
    case _DayAction.payment:
      await openPaymentForm(context, date: date);
    case _DayAction.income:
      await openIncomeForm(context, date: date);
    case _DayAction.nonWorkingDay:
      // M4's one deferred item: the Calendar is the third entry point
      // spec 5.1.2 asks for, and the only one where the date is already known.
      await markNonWorkingDay(context, ref, initial: date, askDate: false);
  }
}

/// One row of the menu: a glyph and a label, matching the Feed's.
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
