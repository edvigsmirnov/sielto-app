import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/incomes/income_form_page.dart';
import 'package:sielto/features/payments/payment_form_page.dart';
import 'package:sielto/features/settings/holidays_page.dart';

enum _DayAction { payment, income, nonWorkingDay }

/// Long-press menu on a calendar day; the Feed's quick-add items on that day.
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
    // Anchored at the finger.
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
          // In Budget mode an income is a top-up of the fund.
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
  HapticFeedback.lightImpact();

  switch (choice) {
    case _DayAction.payment:
      await openPaymentForm(context, date: date);
    case _DayAction.income:
      await openIncomeForm(context, date: date);
    case _DayAction.nonWorkingDay:
      await markNonWorkingDay(context, ref, initial: date, askDate: false);
  }
}

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
