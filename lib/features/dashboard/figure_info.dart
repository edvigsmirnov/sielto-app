import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/ledger/ledger_walker.dart';
import 'package:sielto/domain/value/calendar_date.dart';

/// One line of a worked sum: `+ $300.00 more coming in`.
class SumLine {
  const SumLine(this.sign, this.amount, this.label);

  final String sign;
  final String amount;
  final String label;
}

/// What a Dashboard figure means, worked out in the reader's own numbers.
class FigureInfo {
  const FigureInfo({
    required this.title,
    required this.what,
    this.sum = const <SumLine>[],
    this.note,
    this.advice,
  });

  final String title;
  final String what;

  /// The last line is the result.
  final List<SumLine> sum;

  final String? note;

  /// Only when the figure is short.
  final String? advice;
}

/// Start, income and spending of [run], then what is left or short.
List<SumLine> runSum(
  LedgerRun run,
  MoneyFormat money, {
  required String startLabel,
  String? spendLabel,
}) {
  Decimal income = Decimal.zero;
  Decimal spent = Decimal.zero;
  for (final LedgerStep step in run.steps) {
    if (step.entry.isIncome) {
      income += step.entry.amount;
    } else {
      spent += step.entry.amount;
    }
  }
  final bool short = run.finalBalance < Decimal.zero;
  return <SumLine>[
    SumLine('', money.format(run.available), startLabel),
    if (income > Decimal.zero)
      SumLine('+', money.format(income), tr('info.comingIn')),
    SumLine('−', money.format(spent), spendLabel ?? tr('info.planned')),
    SumLine(
      '=',
      money.format(short ? -run.finalBalance : run.finalBalance),
      tr(short ? 'info.short' : 'info.left'),
    ),
  ];
}

/// The hero figure's explanation; says where the money runs out when it does.
FigureInfo moneyLeftInfo({
  required String title,
  required String what,
  required LedgerRun run,
  required MoneyFormat money,
  required DateLabels dates,
  required CalendarDate today,
  required String startLabel,
  String? spendLabel,
}) {
  final CalendarDate? lastDay = run.lastCoveredDay;
  final bool short = run.hasCutoff && lastDay != null;
  final bool shortToday = short && lastDay.isBefore(today);
  return FigureInfo(
    title: shortToday
        ? tr('info.shortNow')
        : short
        ? tr(
            'info.lastsTitle',
            namedArgs: <String, String>{
              'date': dates.dayMonth(lastDay, reference: today),
            },
          )
        : title,
    what: short
        ? shortToday
              ? tr('info.shortToday')
              : tr(
                  'info.lasts',
                  namedArgs: <String, String>{
                    'date': dates.dayMonth(lastDay, reference: today),
                  },
                )
        : what,
    sum: runSum(run, money, startLabel: startLabel, spendLabel: spendLabel),
    advice: shortToday
        ? tr('info.shortTodayAdvice')
        : short
        ? tr('info.lastsAdvice')
        : null,
  );
}

/// A small (i) that opens [info].
class InfoButton extends StatelessWidget {
  const InfoButton(this.info, {this.dense = false, super.key});

  final FigureInfo info;

  /// Fits a text line, for rows of figures.
  final bool dense;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: tr('info.explain'),
    child: InkWell(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        backgroundColor: context.sage.card,
        builder: (BuildContext context) => _InfoSheet(info),
      ),
      customBorder: const CircleBorder(),
      child: Padding(
        padding: dense
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
            : const EdgeInsets.all(12),
        child: Icon(Icons.info_outline, size: 16, color: context.sage.inkLabel),
      ),
    ),
  );
}

class _InfoSheet extends StatelessWidget {
  const _InfoSheet(this.info);

  final FigureInfo info;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SageSpace.gutter,
          0,
          SageSpace.gutter,
          SageSpace.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(info.title, style: text.titleMedium),
            const SizedBox(height: SageSpace.sm),
            Text(info.what, style: text.bodyMedium),
            if (info.sum.isNotEmpty) ...<Widget>[
              const SizedBox(height: SageSpace.md),
              Container(
                padding: const EdgeInsets.all(SageSpace.md),
                decoration: BoxDecoration(
                  color: sage.accentTint,
                  borderRadius: BorderRadius.circular(SageRadius.button),
                ),
                child: Column(
                  children: <Widget>[
                    for (int i = 0; i < info.sum.length; i++) ...<Widget>[
                      if (i == info.sum.length - 1) ...<Widget>[
                        const SizedBox(height: SageSpace.xs),
                        const Hairline(),
                        const SizedBox(height: SageSpace.xs),
                      ],
                      _SumRow(info.sum[i], result: i == info.sum.length - 1),
                    ],
                  ],
                ),
              ),
            ],
            if (info.note != null) ...<Widget>[
              const SizedBox(height: SageSpace.md),
              Text(
                info.note!,
                style: text.bodySmall?.copyWith(color: sage.inkSecondary),
              ),
            ],
            if (info.advice != null) ...<Widget>[
              const SizedBox(height: SageSpace.md),
              Text(
                info.advice!,
                style: text.bodySmall?.copyWith(color: sage.warningAccent),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SumRow extends StatelessWidget {
  const _SumRow(this.line, {required this.result});

  final SumLine line;
  final bool result;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final TextStyle? style = result ? text.titleSmall : text.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(width: 20, child: Text(line.sign, style: style)),
          Expanded(child: Text(line.label, style: style)),
          Text(
            line.amount,
            style: style?.copyWith(
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
