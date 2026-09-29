import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/format/money_input.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/leaf_loader.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/period/freeze.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/incomes/anchor_help.dart';
import 'package:sielto/features/incomes/income_rule_form_page.dart';
import 'package:sielto/features/incomes/income_rules_page.dart';
import 'package:sielto/features/incomes/income_scope_dialog.dart';
import 'package:sielto/features/incomes/schedule_editor.dart';
import 'package:sielto/features/periods/freeze_providers.dart';
import 'package:sielto/features/periods/freeze_ui.dart';
import 'package:sielto/features/periods/period_choice.dart';
import 'package:sielto/features/space/period_ledger.dart';
import 'package:sielto/features/space/space_ledger.dart';

/// One form for one-off and regular incomes. "Make regular" saves a rule.
Future<void> openIncomeForm(
  BuildContext context, {
  String? incomeId,
  CalendarDate? date,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (BuildContext _) =>
        IncomeFormPage(incomeId: incomeId, initialDate: date),
  ),
);

class IncomeFormPage extends ConsumerStatefulWidget {
  const IncomeFormPage({this.incomeId, this.initialDate, super.key});

  final String? incomeId;
  final CalendarDate? initialDate;

  @override
  ConsumerState<IncomeFormPage> createState() => _IncomeFormPageState();
}

class _IncomeFormPageState extends ConsumerState<IncomeFormPage> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  /// Text appended to a frozen occurrence's note.
  final TextEditingController _addedNote = TextEditingController();

  CalendarDate? _date;
  bool _isReceived = false;

  /// Defaults to the expected date.
  CalendarDate? _actualDate;

  bool _isRegular = false;
  ScheduleDraft _schedule = const ScheduleDraft();

  /// income_driven Spaces only, once an anchor exists.
  bool _isAnchor = true;
  bool _anchorChoiceApplies = false;

  /// This row is an occurrence of an anchor rule.
  bool _isAnchorOccurrence = false;

  Income? _existing;
  bool _loaded = false;
  bool _saving = false;

  /// Frozen: amount, both dates and the receipt flag are read-only.
  FreezeState _freeze = FreezeState.open;

  bool get _isFrozen => _freeze == FreezeState.frozen;

  @override
  void initState() {
    super.initState();
    for (final TextEditingController c in <TextEditingController>[
      _title,
      _amount,
    ]) {
      c.addListener(() => setState(() {}));
    }
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _notes.dispose();
    _addedNote.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final Space space = ref.read(currentSpaceProvider)!;
    final Repositories repos = ref.read(repositoriesProvider);
    final String? id = widget.incomeId;

    if (id != null) {
      final List<Income> rows = await repos.incomes.inSpace(space.id);
      final Income? row = rows.where((Income i) => i.id == id).firstOrNull;
      if (row != null) {
        _existing = row;
        _title.text = row.title;
        _amount.text = row.amount?.toString() ?? '';
        _notes.text = row.notes ?? '';
        _date = row.expectedDate;
        _isReceived = row.isPaid;
        _actualDate = row.actualDate ?? row.expectedDate;
        _freeze = ref.read(freezeLookupProvider).of(row.budgetPeriodId);

        final String? ruleId = row.recurrenceRuleId;
        if (ruleId != null) {
          final List<IncomeRecurrenceRule> anchors = await repos.incomeRules
              .anchorsInSpace(space.id);
          _isAnchorOccurrence = anchors.any(
            (IncomeRecurrenceRule r) => r.id == ruleId,
          );
        }
      }
    } else if (space.budgetMode == BudgetMode.incomeDriven) {
      // The first regular income becomes the anchor without asking.
      final List<IncomeRecurrenceRule> anchors = await repos.incomeRules
          .anchorsInSpace(space.id);
      _anchorChoiceApplies = anchors.isNotEmpty;
    }

    _date ??= widget.initialDate ?? ref.read(spaceClockProvider).today();
    if (mounted) setState(() => _loaded = true);
  }

  /// Null: amount not known yet.
  Decimal? get _parsedAmount {
    final Decimal? value = parseMoney(_amount.text);
    if (value == null || value <= Decimal.zero) return null;
    return value;
  }

  bool get _amountFieldIsWellFormed =>
      _amount.text.trim().isEmpty || _parsedAmount != null;

  /// Saves without an amount, but a received income needs one.
  bool get _isValid =>
      _title.text.trim().isNotEmpty &&
      _amountFieldIsWellFormed &&
      (!_isReceived || _parsedAmount != null) &&
      (!_isRegular || _schedule.isValid) &&
      !_saving;

  Future<void> _save() async {
    final CalendarDate? date = _date;
    if (date == null) return;
    setState(() => _saving = true);

    try {
      final Space space = ref.read(currentSpaceProvider)!;
      final Repositories repos = ref.read(repositoriesProvider);
      final String? notes = _notes.text.trim().isEmpty
          ? null
          : _notes.text.trim();
      final Income? existing = _existing;

      if (existing != null && _isFrozen) {
        await _saveFrozen(existing, repos);
      } else if (existing != null) {
        await _saveExisting(existing, repos, date, notes);
      } else if (_isRegular) {
        await _createRule(space, repos);
      } else {
        await repos.incomes.create(
          spaceId: space.id,
          title: _title.text,
          expectedDate: date,
          amount: _parsedAmount,
          notes: notes,
          isPaid: _isReceived,
        );
      }

      ref.invalidate(periodRefreshProvider);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createRule(Space space, Repositories repos) async {
    final IncomeRecurrenceRule rule = await repos.incomeRules
        .createFirstAsAnchor(
          spaceId: space.id,
          mode: space.budgetMode,
          title: _title.text,
          amount: _parsedAmount,
          scheduleType: _schedule.type,
          fixedDay: _schedule.type == ScheduleType.fixedDate
              ? _schedule.fixedDay
              : null,
          weekdayOrdinal: _schedule.type == ScheduleType.weekdayRule
              ? _schedule.ordinal
              : null,
          weekdayDay: _schedule.type == ScheduleType.weekdayRule
              ? _schedule.weekday
              : null,
          dateRangeStart: _schedule.type == ScheduleType.dateRange
              ? _schedule.rangeStart
              : null,
          dateRangeEnd: _schedule.type == ScheduleType.dateRange
              ? _schedule.rangeEnd
              : null,
          boundaryAnchor: _schedule.type == ScheduleType.boundaryDays
              ? _schedule.boundaryAnchor
              : null,
          boundaryCount: _schedule.type == ScheduleType.boundaryDays
              ? _schedule.boundaryCount
              : null,
        );

    if (_anchorChoiceApplies && _isAnchor) {
      await repos.incomeRules.setAnchor(
        rule.id,
        isAnchor: true,
        mode: space.budgetMode,
      );
    }
    if (space.budgetMode == BudgetMode.incomeDriven &&
        (rule.isAnchor || (_anchorChoiceApplies && _isAnchor)) &&
        mounted) {
      announceAnchor(context, rule.title);
    }
  }

  /// A frozen period allows the title and an appended note.
  Future<void> _saveFrozen(Income existing, Repositories repos) async {
    final String addition = _addedNote.text.trim();
    await repos.incomes.update(
      existing.id,
      title: Value<String>(_title.text),
      notes: addition.isEmpty
          ? const Value<String?>.absent()
          : Value<String?>(
              FreezeEvaluator.appendNote(
                existing.notes,
                addition,
                ref.read(spaceClockProvider).today(),
              ),
            ),
    );
  }

  /// Amount changes on a series ask how far they reach; date and note change
  /// this occurrence only.
  Future<void> _saveExisting(
    Income existing,
    Repositories repos,
    CalendarDate date,
    String? notes,
  ) async {
    IncomeScope scope = IncomeScope.thisOne;
    final bool amountChanged = _parsedAmount != existing.amount;
    if (existing.recurrenceRuleId != null && amountChanged) {
      if (!mounted) return;
      scope = await askIncomeScope(context);
      if (scope == IncomeScope.cancelled) return;
    }

    await repos.incomes.update(
      existing.id,
      title: Value<String>(_title.text),
      amount: Value<Decimal?>(_parsedAmount),
      expectedDate: Value<CalendarDate>(date),
      notes: Value<String?>(notes),
      isPaid: Value<bool>(_isReceived),
      actualDate: Value<CalendarDate?>(_isReceived ? _actualDate : null),
    );

    if (scope == IncomeScope.allFuture) {
      await repos.incomeRules.setAmount(
        existing.recurrenceRuleId!,
        _parsedAmount,
      );
      await repos.incomes.updateFutureAmounts(
        existing.recurrenceRuleId!,
        _parsedAmount,
      );
    }
  }

  Future<void> _delete() async {
    final Income? existing = _existing;
    if (existing == null) return;
    await ref.read(repositoriesProvider).incomes.softDelete(existing.id);
    ref.invalidate(periodRefreshProvider);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openRule() async {
    final String? ruleId = _existing?.recurrenceRuleId;
    if (ruleId == null) return;

    final List<IncomeRecurrenceRule> rules = await ref
        .read(repositoriesProvider)
        .incomeRules
        .inSpace(ref.read(currentSpaceProvider)!.id);
    final IncomeRecurrenceRule? rule = rules
        .where((IncomeRecurrenceRule r) => r.id == ruleId)
        .firstOrNull;
    if (rule == null || !mounted) return;
    await openIncomeRuleForm(context, rule: rule);
  }

  Future<void> _pickDate({required bool actual}) async {
    final CalendarDate current =
        (actual ? _actualDate : _date) ?? ref.read(spaceClockProvider).today();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: current.toUtcMidnight(),
      firstDate: DateTime.utc(current.year - 10),
      lastDate: DateTime.utc(current.year + 15),
    );
    if (picked == null) return;
    setState(() {
      if (actual) {
        _actualDate = CalendarDate.fromDateTime(picked);
      } else {
        _date = CalendarDate.fromDateTime(picked);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Space space = ref.space;
    final String locale = context.locale.toString();
    final MoneyFormat money = MoneyFormat(
      locale: locale,
      currencyCode: space.currencyCode,
    );
    final DateLabels dates = DateLabels(locale);

    if (!_loaded) {
      return const Scaffold(body: Center(child: LeafLoader()));
    }

    final bool isOccurrence = _existing != null;
    final bool partOfSeries = _existing?.recurrenceRuleId != null;

    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: AppBar(
        title: Text(
          isOccurrence
              ? tr('income.edit')
              : (ref.space.budgetMode == BudgetMode.budget
                    ? tr('budget.topUp')
                    : tr('income.add')),
        ),
        actions: <Widget>[
          // No delete in a frozen period or for an anchor occurrence; the rule is
          // deleted from the regular income list.
          if (isOccurrence && !_isFrozen && !_isAnchorOccurrence)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: tr('common.delete'),
              onPressed: _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SageSpace.formGutter),
          children: <Widget>[
            if (_isFrozen) const FreezeNotice(),
            // Link to the rule behind this occurrence.
            if (partOfSeries)
              Padding(
                padding: const EdgeInsets.only(bottom: SageSpace.md),
                child: SageCard(
                  onTap: _openRule,
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.repeat,
                        size: 18,
                        color: context.sage.inkLabel,
                      ),
                      const SizedBox(width: SageSpace.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              tr('income.partOfSeries'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tr('income.editRule'),
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(color: context.sage.accentStrong),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: context.sage.inkLabel,
                      ),
                    ],
                  ),
                ),
              ),
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
              child: TextField(
                controller: _amount,
                enabled: !_isFrozen,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,\s]')),
                ],
                decoration: InputDecoration(
                  suffixText: money.symbol,
                  hintText: tr('income.amountOptional'),
                ),
              ),
            ),
            const SizedBox(height: SageSpace.lg),

            // Regular incomes take dates from the schedule.
            if (!_isRegular) ...<Widget>[
              LabelledField(
                label: tr('income.fieldDate'),
                child: DateField(
                  label: dates.dayMonth(_date!),
                  onTap: _isFrozen ? null : () => _pickDate(actual: false),
                ),
              ),
              const SizedBox(height: SageSpace.sm),
              _LandsIn(date: _date!, amount: _parsedAmount, money: money),
              const SizedBox(height: SageSpace.lg),
            ],

            if (!isOccurrence) ...<Widget>[
              SwitchListTile.adaptive(
                value: _isRegular,
                contentPadding: EdgeInsets.zero,
                title: Text(tr('income.makeRegular')),
                subtitle: Text(tr('income.makeRegularHint')),
                onChanged: (bool value) => setState(() => _isRegular = value),
              ),
              if (_isRegular) ...<Widget>[
                const SizedBox(height: SageSpace.md),
                ScheduleEditor(
                  draft: _schedule,
                  onChanged: (ScheduleDraft next) =>
                      setState(() => _schedule = next),
                ),
                // income_driven only.
                if (_anchorChoiceApplies &&
                    space.budgetMode == BudgetMode.incomeDriven) ...<Widget>[
                  const SizedBox(height: SageSpace.lg),
                  LabelledField(
                    label: tr('income.role'),
                    child: SegmentedChoice<bool>(
                      values: const <bool>[true, false],
                      selected: _isAnchor,
                      labelOf: (bool anchor) => anchor
                          ? tr('income.roleAnchor')
                          : tr('income.roleAdditional'),
                      onChanged: (bool anchor) =>
                          setState(() => _isAnchor = anchor),
                    ),
                  ),
                  const SizedBox(height: SageSpace.xs),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _isAnchor
                              ? tr('income.roleAnchorHint')
                              : tr('income.roleAdditionalHint'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const AnchorHelpButton(),
                    ],
                  ),
                ],
              ],
              const SizedBox(height: SageSpace.lg),
            ],

            if (_isFrozen)
              _AppendNoteField(
                existing: _existing?.notes,
                controller: _addedNote,
              )
            else
              LabelledField(
                label: tr('income.fieldNotes'),
                child: TextField(
                  controller: _notes,
                  maxLines: 3,
                  maxLength: 5000,
                ),
              ),

            if (!_isRegular) ...<Widget>[
              SwitchListTile.adaptive(
                value: _isReceived,
                contentPadding: EdgeInsets.zero,
                title: Text(tr('income.markReceived')),
                subtitle: _isReceived && _parsedAmount == null
                    ? Text(
                        tr('income.amountRequired'),
                        style: TextStyle(color: context.sage.danger),
                      )
                    : null,
                onChanged: _isFrozen
                    ? null
                    : (bool value) => setState(() {
                        _isReceived = value;
                        _actualDate ??= _date;
                      }),
              ),
              // Actual receipt date. Changes no calculation.
              if (_isReceived) ...<Widget>[
                const SizedBox(height: SageSpace.sm),
                LabelledField(
                  label: tr('income.fieldActualDate'),
                  child: DateField(
                    label: dates.dayMonth(_actualDate ?? _date!),
                    onTap: _isFrozen ? null : () => _pickDate(actual: true),
                  ),
                ),
                if (_actualDate != null && _actualDate != _date)
                  Padding(
                    padding: const EdgeInsets.only(top: SageSpace.xs),
                    child: Text(
                      tr('income.actualDateNote'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ],

            const SizedBox(height: SageSpace.lg),
            FilledButton(
              onPressed: _isValid ? _save : null,
              child: Text(tr('common.save')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Existing note and a field that appends to it.
class _AppendNoteField extends StatelessWidget {
  const _AppendNoteField({required this.existing, required this.controller});

  final String? existing;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      if (existing != null && existing!.trim().isNotEmpty) ...<Widget>[
        LabelledField(
          label: tr('income.fieldNotes'),
          child: SageCard(
            child: Text(
              existing!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
        const SizedBox(height: SageSpace.lg),
      ],
      LabelledField(
        label: tr('freeze.addNote'),
        child: TextField(
          controller: controller,
          maxLines: 3,
          maxLength: 5000,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: tr('freeze.addNoteHint')),
        ),
      ),
    ],
  );
}

/// Which cycle a one-off income joins and its effect on free money.
class _LandsIn extends ConsumerWidget {
  const _LandsIn({
    required this.date,
    required this.amount,
    required this.money,
  });

  final CalendarDate date;
  final Decimal? amount;
  final MoneyFormat money;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(currentSpaceProvider)?.budgetMode !=
        BudgetMode.incomeDriven) {
      return const SizedBox.shrink();
    }

    final BudgetPeriod? period = periodsAround(
      ref.watch(incomePeriodsProvider),
      date,
    ).current;
    final CalendarDate? end = period?.endDate;
    if (period == null || end == null) return const SizedBox.shrink();

    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    final DateLabels dates = DateLabels(context.locale.toString());

    // Null while the amount is empty.
    final PeriodLedger ledger = buildPeriodLedger(
      period: period,
      payments: ref.watch(spacePaymentsProvider).value ?? const <Payment>[],
      incomes: ref.watch(spaceIncomesProvider).value ?? const <Income>[],
      anchorRuleIds: <String>{
        for (final IncomeRecurrenceRule r
            in ref.watch(incomeRulesProvider).value ??
                const <IncomeRecurrenceRule>[])
          if (r.isAnchor) r.id,
      },
      today: ref.watch(spaceClockProvider).today(),
    );
    final Decimal? free = ledger.freeCash;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SageSpace.md),
      decoration: BoxDecoration(
        color: sage.accentTint,
        borderRadius: BorderRadius.circular(SageRadius.button),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            tr(
              'income.landsIn',
              namedArgs: <String, String>{
                'period':
                    '${dates.short(period.startDate)} – ${dates.short(end)}',
              },
            ),
            style: text.bodySmall?.copyWith(color: sage.inkSecondary),
          ),
          if (free != null && amount != null) ...<Widget>[
            const SizedBox(height: SageSpace.xs),
            Row(
              children: <Widget>[
                Text(
                  money.format(free),
                  style: text.titleSmall?.copyWith(color: sage.inkSecondary),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: SageSpace.sm),
                  child: Icon(
                    Icons.arrow_forward,
                    size: 16,
                    color: sage.inkLabel,
                  ),
                ),
                Flexible(
                  child: Text(
                    money.format(free + amount!),
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium?.copyWith(color: sage.accentStrong),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Tappable date field. Shared with the receipt dialog.
class DateField extends StatelessWidget {
  const DateField({required this.label, required this.onTap, super.key});

  final String label;

  /// Null when the period is frozen.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SageRadius.input),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: sage.card,
          borderRadius: BorderRadius.circular(SageRadius.input),
          border: Border.all(color: sage.border),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
            ),
            Icon(Icons.calendar_today_outlined, size: 18, color: sage.inkLabel),
          ],
        ),
      ),
    );
  }
}
