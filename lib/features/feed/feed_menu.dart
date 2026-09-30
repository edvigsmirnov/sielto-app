import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/ui/action_sheet.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/feed/feed_model.dart';
import 'package:sielto/features/incomes/income_form_page.dart';
import 'package:sielto/features/payments/payment_form_page.dart';
import 'package:sielto/features/settings/holidays_page.dart';

enum _QuickAdd { payment, income, nonWorkingDay }

/// Add an expense, an income or a day off on [date].
List<SheetAction<_QuickAdd>> _quickAdd(WidgetRef ref) =>
    <SheetAction<_QuickAdd>>[
      SheetAction<_QuickAdd>(
        Icons.remove_circle_outline,
        tr('payment.add'),
        _QuickAdd.payment,
      ),
      SheetAction<_QuickAdd>(
        Icons.add_circle_outline,
        // In Budget mode an income is a top-up of the fund.
        ref.read(currentSpaceProvider)!.budgetMode == BudgetMode.budget
            ? tr('budget.topUp')
            : tr('income.add'),
        _QuickAdd.income,
      ),
      SheetAction<_QuickAdd>(
        Icons.event_busy_outlined,
        tr('holidays.markDay'),
        _QuickAdd.nonWorkingDay,
      ),
    ];

/// The + button and a Calendar day's long press share these actions.
Future<void> showQuickAddMenu(
  BuildContext context,
  WidgetRef ref, {
  required CalendarDate date,
  required String title,
  bool askDate = true,
}) async {
  HapticFeedback.lightImpact();
  final _QuickAdd? choice = await showActionSheet<_QuickAdd>(
    context,
    title: title,
    groups: <List<SheetAction<_QuickAdd>>>[_quickAdd(ref)],
  );
  if (choice == null || !context.mounted) return;
  HapticFeedback.lightImpact();

  switch (choice) {
    case _QuickAdd.payment:
      await openPaymentForm(context, date: date);
    case _QuickAdd.income:
      await openIncomeForm(context, date: date);
    case _QuickAdd.nonWorkingDay:
      await markNonWorkingDay(context, ref, initial: date, askDate: askDate);
  }
}

enum RecordAction { addBefore, addAfter, duplicateBefore, duplicateAfter }

/// Add or duplicate on a neighbouring day.
List<SheetAction<Object>> recordActions(FeedRecord record) =>
    <SheetAction<Object>>[
      SheetAction<Object>(
        Icons.arrow_upward,
        tr('feed.addBefore'),
        RecordAction.addBefore,
      ),
      SheetAction<Object>(
        Icons.arrow_downward,
        tr('feed.addAfter'),
        RecordAction.addAfter,
      ),
      if (!record.isIncome) ...<SheetAction<Object>>[
        SheetAction<Object>(
          Icons.content_copy_outlined,
          tr('feed.duplicateBefore'),
          RecordAction.duplicateBefore,
        ),
        SheetAction<Object>(
          Icons.content_copy,
          tr('feed.duplicateAfter'),
          RecordAction.duplicateAfter,
        ),
      ],
    ];

Future<void> runRecordAction(
  BuildContext context,
  WidgetRef ref,
  FeedRecord record,
  RecordAction action,
) => switch (action) {
  RecordAction.addBefore => _addOn(context, record, record.date.addDays(-1)),
  RecordAction.addAfter => _addOn(context, record, record.date.addDays(1)),
  RecordAction.duplicateBefore => _duplicate(
    context,
    ref,
    record,
    record.date.addDays(-1),
  ),
  RecordAction.duplicateAfter => _duplicate(
    context,
    ref,
    record,
    record.date.addDays(1),
  ),
};

/// Long-press menu on a row outside the Feed.
Future<void> showRecordMenu(
  BuildContext context,
  WidgetRef ref, {
  required FeedRecord record,
}) async {
  final Object? choice = await showActionSheet<Object>(
    context,
    title: record.title,
    groups: <List<SheetAction<Object>>>[recordActions(record)],
  );
  if (choice is RecordAction && context.mounted) {
    await runRecordAction(context, ref, record, choice);
  }
}

/// Empty form on the neighbouring day.
Future<void> _addOn(
  BuildContext context,
  FeedRecord record,
  CalendarDate date,
) => record.isIncome
    ? openIncomeForm(context, date: date)
    : openPaymentForm(context, date: date);

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
