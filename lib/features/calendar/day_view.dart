import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/settings/local_settings.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/calendar/calendar_data.dart';
import 'package:sielto/features/feed/feed_model.dart';
import 'package:sielto/features/feed/feed_row.dart';

/// Day totals and records. Reuses the Feed row.
class DayView extends StatelessWidget {
  const DayView({
    required this.day,
    required this.records,
    required this.today,
    required this.categories,
    required this.density,
    required this.money,
    required this.onEdit,
    required this.onTogglePaid,
    required this.onDelete,
    required this.onHoldRecord,
    required this.isFrozen,
    this.dayOff,
    super.key,
  });

  final CalendarDate day;
  final DayRecords records;
  final CalendarDate today;
  final Map<String, Category> categories;
  final FeedDensity density;
  final MoneyFormat money;
  final ValueChanged<FeedRecord> onEdit;
  final ValueChanged<FeedRecord> onTogglePaid;
  final ValueChanged<FeedRecord> onDelete;
  final ValueChanged<FeedRecord> onHoldRecord;

  final bool Function(String? budgetPeriodId) isFrozen;

  /// Null on a working day; otherwise holiday names, empty when unknown.
  final List<String>? dayOff;

  @override
  Widget build(BuildContext context) {
    final List<FeedRecord> rows =
        <FeedRecord>[
          for (final Payment p in records.payments) FeedRecord.fromPayment(p),
          for (final Income i in records.incomes) FeedRecord.fromIncome(i),
        ]..sort(
          (FeedRecord a, FeedRecord b) =>
              compareInDay(a, b, FeedOrderMode.grouped),
        );

    Decimal expenses = Decimal.zero;
    Decimal income = Decimal.zero;
    for (final FeedRecord r in rows) {
      final Decimal? amount = r.amount;
      if (amount == null) continue;
      if (r.isIncome) {
        income += amount;
      } else {
        expenses += amount;
      }
    }

    return Column(
      children: <Widget>[
        if (dayOff != null) ...<Widget>[
          _DayOffBanner(names: dayOff!),
          const SizedBox(height: SageSpace.md),
        ],
        Row(
          children: <Widget>[
            Expanded(
              child: _TotalCard(
                label: tr('calendar.dayExpenses'),
                // Zero prints unsigned.
                text: expenses > Decimal.zero
                    ? money.formatSigned(-expenses)
                    : money.format(Decimal.zero),
                tinted: false,
              ),
            ),
            const SizedBox(width: SageSpace.sm),
            Expanded(
              child: _TotalCard(
                label: tr('calendar.dayIncome'),
                text: income > Decimal.zero
                    ? money.formatSigned(income)
                    : money.format(Decimal.zero),
                tinted: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: SageSpace.md),
        Expanded(
          child: rows.isEmpty
              ? EmptyState(message: tr('calendar.dayEmpty'))
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: rows.length,
                  separatorBuilder: (BuildContext _, int _) => const Hairline(),
                  itemBuilder: (BuildContext context, int index) {
                    final FeedRecord record = rows[index];
                    return FeedRowTile(
                      key: ValueKey<String>(record.id),
                      record: record,
                      // No coverage in a single day.
                      isCovered: true,
                      density: density,
                      money: money,
                      category: record.categoryId == null
                          ? null
                          : categories[record.categoryId],
                      onTap: () => onEdit(record),
                      onTogglePaid: () => onTogglePaid(record),
                      onDelete: () => onDelete(record),
                      onLongPress: () => onHoldRecord(record),
                      isFrozen: isFrozen(record.budgetPeriodId),
                      isOverdue: record.isOverdue(today),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _DayOffBanner extends StatelessWidget {
  const _DayOffBanner({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SageSpace.md),
      decoration: BoxDecoration(
        color: sage.warningTint,
        borderRadius: BorderRadius.circular(SageRadius.button),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.celebration_outlined, size: 20, color: sage.warning),
          const SizedBox(width: SageSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  names.isEmpty ? tr('calendar.holiday') : names.first,
                  style: text.titleSmall?.copyWith(color: sage.warning),
                ),
                for (final String other in names.skip(1))
                  Text(
                    other,
                    style: text.bodySmall?.copyWith(color: sage.warning),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.label,
    required this.text,
    required this.tinted,
  });

  final String label;
  final String text;

  /// Accent tint.
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme style = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: SageSpace.md),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tinted ? sage.accentTint : sage.card,
        borderRadius: BorderRadius.circular(SageRadius.button),
        border: Border.all(color: sage.border),
      ),
      child: Column(
        children: <Widget>[
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.bodySmall?.copyWith(color: sage.inkLabel),
          ),
          const SizedBox(height: 2),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.titleSmall?.copyWith(
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
