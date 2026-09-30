import 'package:drift/drift.dart' show Value;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/feed/feed_model.dart';
import 'package:sielto/features/incomes/income_form_page.dart';
import 'package:sielto/features/incomes/receipt_dialog.dart';
import 'package:sielto/features/payments/payment_form_page.dart';
import 'package:sielto/features/periods/freeze_ui.dart';

/// Record actions shared by the Feed, the Calendar and the overdue list.
void editRecord(BuildContext context, FeedRecord record) {
  if (record.isIncome) {
    openIncomeForm(context, incomeId: record.id, date: record.date);
    return;
  }
  openPaymentForm(context, paymentId: record.id, date: record.date);
}

/// Unmarking a mandatory payment asks for confirmation.
Future<void> togglePaid(
  BuildContext context,
  WidgetRef ref,
  FeedRecord record,
) async {
  final Repositories repos = ref.read(repositoriesProvider);
  final bool next = !record.isPaid;

  if (!next &&
      record.isMandatory &&
      !await confirmMandatory(context, MandatoryChange.unpay)) {
    return;
  }
  if (!context.mounted) return;

  if (!record.isIncome) {
    await guardWrite(
      context,
      () => repos.payments.setPaid(record.id, isPaid: next),
    );
    return;
  }

  if (next && record.amount == null) {
    // A receipt needs an amount.
    openIncomeForm(context, incomeId: record.id, date: record.date);
    return;
  }

  CalendarDate? actual;
  if (next) {
    actual = await askReceiptDate(context, expected: record.date);
    if (actual == null || !context.mounted) return;
  }

  await guardWrite(
    context,
    () => next
        ? repos.incomes.markReceived(record.id, actualDate: actual)
        : repos.incomes.update(
            record.id,
            isPaid: const Value<bool>(false),
            actualDate: const Value<CalendarDate?>(null),
          ),
  );
  // An early anchor moves its cycle.
  ref.invalidate(periodRefreshProvider);
}

Future<void> deleteRecord(
  BuildContext context,
  WidgetRef ref,
  FeedRecord record,
) async {
  if (record.isMandatory &&
      !await confirmMandatory(context, MandatoryChange.delete)) {
    return;
  }
  if (!context.mounted) return;
  final Repositories repos = ref.read(repositoriesProvider);

  final bool deleted = await guardWrite(
    context,
    () => record.isIncome
        ? repos.incomes.softDelete(record.id)
        : repos.payments.softDelete(record.id),
  );
  ref.invalidate(periodRefreshProvider);
  if (!deleted || !context.mounted) return;
  showUndoSnackbar(
    context,
    message: tr(
      'feed.deleted',
      namedArgs: <String, String>{'title': record.title},
    ),
    onUndo: () => record.isIncome
        ? repos.incomes.restore(record.id)
        : repos.payments.restore(record.id),
  );
}
