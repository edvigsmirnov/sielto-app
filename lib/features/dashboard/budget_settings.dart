import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/format/money_input.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/form_fields.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/space/budget_ledger.dart';

/// Edits the fund target. Empty clears it.
Future<void> editBudgetFund(
  BuildContext context,
  WidgetRef ref, {
  required BudgetLedger ledger,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (BuildContext _) => _FundSheet(ledger: ledger),
);

class _FundSheet extends ConsumerStatefulWidget {
  const _FundSheet({required this.ledger});

  final BudgetLedger ledger;

  @override
  ConsumerState<_FundSheet> createState() => _FundSheetState();
}

class _FundSheetState extends ConsumerState<_FundSheet> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.ledger.target?.toString() ?? '',
  );

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  bool get _isValid {
    if (_amount.text.trim().isEmpty) return true;
    final Decimal? value = parseMoney(_amount.text);
    return value != null && value >= Decimal.zero;
  }

  Future<void> _save() async {
    if (!_isValid) return;
    final Decimal? value = _amount.text.trim().isEmpty
        ? null
        : parseMoney(_amount.text);
    await ref
        .read(repositoriesProvider)
        .periods
        .setBudgetTarget(widget.ledger.period.id, value);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final MoneyFormat money = MoneyFormat(
      locale: context.locale.toString(),
      currencyCode: ref.space.currencyCode,
    );

    return FormSheet(
      title: tr('budget.fundSheetTitle'),
      body: tr('budget.fundSheetBody'),
      action: FilledButton(
        onPressed: _isValid ? _save : null,
        child: Text(tr('common.save')),
      ),
      children: <Widget>[
        MoneyField(
          controller: _amount,
          symbol: money.symbol,
          autofocus: true,
          hintText: tr('budget.targetHint'),
          onSubmitted: (String _) => _save(),
        ),
      ],
    );
  }
}

/// Edits the event date and whether it is hard.
Future<void> editBudgetDeadline(
  BuildContext context,
  WidgetRef ref, {
  required BudgetLedger ledger,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (BuildContext _) => _DeadlineSheet(ledger: ledger),
);

class _DeadlineSheet extends ConsumerStatefulWidget {
  const _DeadlineSheet({required this.ledger});

  final BudgetLedger ledger;

  @override
  ConsumerState<_DeadlineSheet> createState() => _DeadlineSheetState();
}

class _DeadlineSheetState extends ConsumerState<_DeadlineSheet> {
  late CalendarDate? _date = widget.ledger.deadline;
  late bool _isHard = widget.ledger.deadlineIsHard;

  Future<void> _pick() async {
    final CalendarDate start = _date ?? widget.ledger.today;
    final CalendarDate? picked = await pickDate(context, start);
    if (picked == null) return;
    setState(() => _date = picked);
  }

  Future<void> _save() async {
    await ref
        .read(repositoriesProvider)
        .periods
        .setDeadline(widget.ledger.period.id, date: _date, isHard: _isHard);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    final DateLabels dates = DateLabels(context.locale.toString());

    return FormSheet(
      title: tr('budget.deadlineSheetTitle'),
      body: tr('budget.deadlineSheetBody'),
      action: FilledButton(onPressed: _save, child: Text(tr('common.save'))),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: DateField(
                label: _date == null
                    ? tr('budget.noDeadline')
                    : dates.dayMonth(_date!, reference: widget.ledger.today),
                onTap: _pick,
              ),
            ),
            if (_date != null)
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: tr('common.clear'),
                color: sage.inkLabel,
                onPressed: () => setState(() {
                  _date = null;
                  _isHard = false;
                }),
              ),
          ],
        ),
        const SizedBox(height: SageSpace.md),
        // Soft: a marker only. Hard: refuses later records.
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _isHard,
          onChanged: _date == null
              ? null
              : (bool value) => setState(() => _isHard = value),
          title: Text(tr('budget.hardDeadline'), style: text.bodyLarge),
          subtitle: Text(tr('budget.hardDeadlineHint'), style: text.bodySmall),
        ),
      ],
    );
  }
}
