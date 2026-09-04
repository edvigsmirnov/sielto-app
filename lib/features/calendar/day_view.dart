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

/// The Day view: the two totals, then every record on the day (spec 8.1).
///
/// The only Calendar scale that loads rows, and the reason the other three
/// need no detail query. It reuses the Feed's row so both screens answer a tap
/// or a swipe the same way — a record is the same record whichever list it is
/// read in.
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

  /// Whether a record's period has closed (spec 5.5).
  final bool Function(String? budgetPeriodId) isFrozen;

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
        Row(
          children: <Widget>[
            Expanded(
              child: _TotalCard(
                label: tr('calendar.dayExpenses'),
                // Signed, and zero prints as zero rather than "-0": a day with
                // nothing spent has spent nothing, not a negative amount.
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
              // No button here: the one that adds to this day is the floating
              // one, which is on screen either way.
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
                      // The Day view is a calendar, not a plan: coverage is a
                      // property of the walk over a whole cycle and saying
                      // anything about it from one day would be a guess.
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

/// One of the two figures over the list (design section 7).
class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.label,
    required this.text,
    required this.tinted,
  });

  final String label;
  final String text;

  /// The income card carries the accent tint, matching the Feed's totals where
  /// what comes in is the figure the rest is measured against.
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
