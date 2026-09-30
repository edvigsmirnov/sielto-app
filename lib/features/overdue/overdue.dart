import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/settings/local_settings.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/feed/feed_menu.dart';
import 'package:sielto/features/feed/feed_model.dart';
import 'package:sielto/features/feed/feed_row.dart';
import 'package:sielto/features/feed/record_actions.dart';
import 'package:sielto/features/payments/payment_form_page.dart';
import 'package:sielto/features/periods/freeze_providers.dart';
import 'package:sielto/features/periods/freeze_ui.dart';
import 'package:sielto/features/space/space_ledger.dart';

/// Past-due unpaid payments, in any period.
@immutable
class OverdueSummary {
  const OverdueSummary({required this.payments, required this.total});

  /// Oldest first.
  final List<Payment> payments;

  final Decimal total;

  int get count => payments.length;

  bool get isEmpty => payments.isEmpty;
}

/// Unpaid and due before today. Incomes are excluded.
OverdueSummary summariseOverdue(List<Payment> payments, CalendarDate today) {
  final List<Payment> missed =
      payments
          .where((Payment p) => !p.isPaid && p.dueDate.isBefore(today))
          .toList()
        ..sort((Payment a, Payment b) => a.dueDate.compareTo(b.dueDate));

  return OverdueSummary(
    payments: missed,
    total: missed.fold(
      Decimal.zero,
      (Decimal sum, Payment p) => sum + p.amount,
    ),
  );
}

final Provider<OverdueSummary> overduePaymentsProvider =
    Provider<OverdueSummary>(
      (Ref ref) => summariseOverdue(
        ref.watch(spacePaymentsProvider).value ?? const <Payment>[],
        ref.watch(spaceClockProvider).today(),
      ),
    );

/// Total owed late, opening [OverduePage]. Draws nothing when empty.
class OverdueChip extends ConsumerWidget {
  const OverdueChip({required this.money, this.margin, super.key});

  final MoneyFormat money;

  /// Applied only when the chip shows.
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SageColors sage = context.sage;
    final OverdueSummary summary = ref.watch(overduePaymentsProvider);
    if (summary.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: InkWell(
        onTap: () => openOverduePage(context, money: money),
        borderRadius: BorderRadius.circular(SageRadius.button),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SageSpace.md,
            vertical: SageSpace.sm,
          ),
          decoration: BoxDecoration(
            color: sage.dangerTint,
            borderRadius: BorderRadius.circular(SageRadius.button),
            border: Border.all(color: sage.danger.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.warning_amber_rounded, size: 18, color: sage.danger),
              const SizedBox(width: SageSpace.sm),
              Expanded(
                child: Text(
                  tr('overdue.title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: sage.danger),
                ),
              ),
              Text(
                money.format(summary.total),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: sage.danger,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              const SizedBox(width: SageSpace.xs),
              Icon(Icons.chevron_right, size: 18, color: sage.danger),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> openOverduePage(
  BuildContext context, {
  required MoneyFormat money,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (BuildContext _) => OverduePage(money: money),
  ),
);

/// Every missed payment, oldest first, as Feed rows.
class OverduePage extends ConsumerWidget {
  const OverduePage({required this.money, super.key});

  final MoneyFormat money;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SageColors sage = context.sage;
    final OverdueSummary summary = ref.watch(overduePaymentsProvider);
    final CalendarDate today = ref.watch(spaceClockProvider).today();
    final FeedDensity density = ref.watch(feedDensityProvider);
    final Map<String, Category> categories =
        ref.watch(categoryIndexProvider).value ?? const <String, Category>{};
    final FreezeLookup freeze = ref.watch(freezeLookupProvider);
    final DateLabels dates = DateLabels(context.locale.toString());

    return Scaffold(
      backgroundColor: sage.surface,
      appBar: AppBar(
        title: Text(tr('overdue.title')),
        bottom: summary.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(44),
                child: _Total(summary: summary, money: money),
              ),
      ),
      body: summary.isEmpty
          ? EmptyState(message: tr('overdue.allSettled'))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: SageSpace.xl),
              itemCount: summary.payments.length,
              itemBuilder: (BuildContext context, int index) {
                final Payment payment = summary.payments[index];
                final Payment? previous = index == 0
                    ? null
                    : summary.payments[index - 1];
                final FeedRecord record = FeedRecord.fromPayment(payment);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // One heading per day.
                    if (previous == null || previous.dueDate != payment.dueDate)
                      _DayHeading(
                        label: dates.dayMonth(
                          payment.dueDate,
                          reference: today,
                        ),
                      ),
                    FeedRowTile(
                      key: ValueKey<String>('overdue:${payment.id}'),
                      record: record,
                      isCovered: true,
                      density: density,
                      money: money,
                      category: record.categoryId == null
                          ? null
                          : categories[record.categoryId],
                      isFrozen: freeze.isFrozen(payment.budgetPeriodId),
                      isOverdue: true,
                      onTap: () =>
                          openPaymentForm(context, paymentId: payment.id),
                      onTogglePaid: () => _settle(context, ref, record),
                      onDelete: () => deleteRecord(context, ref, record),
                      onLongPress: () => showRecordMenu(
                        context,
                        ref,
                        record: record,
                        today: today,
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  /// Marks paid without asking.
  Future<void> _settle(
    BuildContext context,
    WidgetRef ref,
    FeedRecord record,
  ) => guardWrite(
    context,
    () => ref
        .read(repositoriesProvider)
        .payments
        .setPaid(record.id, isPaid: true),
  );
}

/// Count and total.
class _Total extends StatelessWidget {
  const _Total({required this.summary, required this.money});

  final OverdueSummary summary;
  final MoneyFormat money;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SageSpace.gutter,
        0,
        SageSpace.gutter,
        SageSpace.md,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              plural('overdue.count', summary.count),
              style: text.bodyMedium?.copyWith(color: sage.inkLabel),
            ),
          ),
          Text(
            money.format(summary.total),
            style: text.titleMedium?.copyWith(
              color: sage.danger,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Day heading, in red.
class _DayHeading extends StatelessWidget {
  const _DayHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SageSpace.gutter,
      SageSpace.md,
      SageSpace.gutter,
      SageSpace.xs,
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: context.sage.danger),
    ),
  );
}
