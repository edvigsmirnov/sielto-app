import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/format/money_input.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/core/ui/form_fields.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/incomes/schedule_editor.dart';
import 'package:sielto/features/periods/holiday_service.dart';
import 'package:sielto/features/periods/period_service.dart';

/// Edits a regular income's rule. The occurrence form edits one month.
Future<void> openIncomeRuleForm(
  BuildContext context, {
  required IncomeRecurrenceRule rule,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (BuildContext _) => IncomeRuleFormPage(rule: rule),
  ),
);

class IncomeRuleFormPage extends ConsumerStatefulWidget {
  const IncomeRuleFormPage({required this.rule, super.key});

  final IncomeRecurrenceRule rule;

  @override
  ConsumerState<IncomeRuleFormPage> createState() => _IncomeRuleFormPageState();
}

class _IncomeRuleFormPageState extends ConsumerState<IncomeRuleFormPage> {
  late final TextEditingController _title = TextEditingController(
    text: widget.rule.title,
  );
  late final TextEditingController _amount = TextEditingController(
    text: widget.rule.amount?.toString() ?? '',
  );

  late ScheduleDraft _schedule = _draftOf(widget.rule);
  bool _saving = false;

  static ScheduleDraft _draftOf(IncomeRecurrenceRule rule) => ScheduleDraft(
    type: rule.scheduleType,
    fixedDay: rule.fixedDay ?? 1,
    ordinal: rule.weekdayOrdinal ?? WeekdayOrdinal.first,
    weekday: rule.weekdayDay ?? Weekday.monday,
    rangeStart: rule.dateRangeStart ?? 23,
    rangeEnd: rule.dateRangeEnd ?? 25,
    boundaryAnchor: rule.boundaryAnchor ?? BoundaryAnchor.start,
    boundaryCount: rule.boundaryCount ?? 3,
  );

  @override
  void initState() {
    super.initState();
    for (final TextEditingController c in <TextEditingController>[
      _title,
      _amount,
    ]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  Decimal? get _parsedAmount {
    final Decimal? value = parseMoney(_amount.text);
    if (value == null || value <= Decimal.zero) return null;
    return value;
  }

  bool get _amountIsWellFormed =>
      _amount.text.trim().isEmpty || _parsedAmount != null;

  bool get _isValid =>
      _title.text.trim().isNotEmpty &&
      _amountIsWellFormed &&
      _schedule.isValid &&
      !_saving;

  bool get _scheduleChanged => _schedule != _draftOf(widget.rule);

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final Repositories repos = ref.read(repositoriesProvider);
      final Decimal? amount = _parsedAmount;

      await repos.incomeRules.updateRule(
        widget.rule.id,
        title: _title.text,
        amount: amount,
        scheduleType: _schedule.type,
        fixedDay: _schedule.fixedDayOrNull,
        weekdayOrdinal: _schedule.ordinalOrNull,
        weekdayDay: _schedule.weekdayOrNull,
        dateRangeStart: _schedule.rangeStartOrNull,
        dateRangeEnd: _schedule.rangeEndOrNull,
        boundaryAnchor: _schedule.boundaryAnchorOrNull,
        boundaryCount: _schedule.boundaryCountOrNull,
      );

      if (amount != widget.rule.amount) {
        await repos.incomes.updateFutureAmounts(
          widget.rule.id,
          amount,
          from: ref.read(spaceClockProvider).today(),
        );
      }

      if (_scheduleChanged) await _regenerateOccurrences();

      ref.invalidate(periodRefreshProvider);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Puts upcoming occurrences back on the schedule. Returns rows changed.
  Future<int> _regenerateOccurrences() async {
    final ResolvedCalendar resolved = await ref.read(
      resolvedCalendarProvider.future,
    );
    return PeriodService(
      repos: ref.read(repositoriesProvider),
      calendar: resolved.calendar,
      missingHolidayYears: resolved.missingYears,
    ).regenerate(
      ref.read(currentSpaceProvider)!,
      widget.rule.id,
      ref.read(spaceClockProvider).today(),
    );
  }

  Future<void> _regenerate() async {
    final bool confirmed = await confirmDialog(
      context,
      title: tr('income.regenerateTitle'),
      body: tr(
        'income.regenerateBody',
        namedArgs: <String, String>{'title': widget.rule.title},
      ),
      confirmLabel: tr('income.regenerate'),
    );
    if (!confirmed || !mounted) return;

    setState(() => _saving = true);
    try {
      final int changed = await _regenerateOccurrences();
      ref.invalidate(periodRefreshProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              changed == 0
                  ? tr('income.regenerateNothing')
                  : plural('income.regenerated', changed),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Space space = ref.space;
    final MoneyFormat money = MoneyFormat(
      locale: context.locale.toString(),
      currencyCode: space.currencyCode,
    );

    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: AppBar(title: Text(tr('income.editRule'))),
      bottomNavigationBar: FormActionBar(
        child: FilledButton(
          onPressed: _isValid ? _save : null,
          child: Text(tr('common.save')),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SageSpace.formGutter),
          children: <Widget>[
            LabelledField(
              label: tr('income.fieldTitle'),
              child: TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
            const SizedBox(height: SageSpace.lg),
            LabelledField(
              label: tr('income.fieldAmount'),
              child: MoneyField(
                controller: _amount,
                symbol: money.symbol,
                hintText: tr('income.amountOptional'),
              ),
            ),
            const SizedBox(height: SageSpace.xs),
            Text(
              tr('income.ruleAmountHint'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: SageSpace.lg),
            ScheduleEditor(
              draft: _schedule,
              onChanged: (ScheduleDraft next) =>
                  setState(() => _schedule = next),
            ),
            if (_scheduleChanged) ...<Widget>[
              const SizedBox(height: SageSpace.sm),
              Text(
                tr('income.ruleScheduleHint'),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: context.sage.warning),
              ),
            ],
            if (space.budgetMode == BudgetMode.incomeDriven) ...<Widget>[
              const SizedBox(height: SageSpace.sm),
              TextButton.icon(
                onPressed: _saving ? null : _regenerate,
                icon: const Icon(Icons.restart_alt),
                label: Text(tr('income.regenerate')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
