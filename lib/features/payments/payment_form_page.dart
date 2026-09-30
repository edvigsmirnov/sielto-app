import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/format/money_input.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/time/space_clock.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/core/ui/form_fields.dart';
import 'package:sielto/core/ui/leaf_loader.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/ledger/ledger_entry.dart';
import 'package:sielto/domain/ledger/ledger_walker.dart';
import 'package:sielto/domain/period/freeze.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/payments/category_picker.dart';
import 'package:sielto/features/payments/recurrence.dart';
import 'package:sielto/features/payments/series_scope_dialog.dart';
import 'package:sielto/features/payments/title_field.dart';
import 'package:sielto/features/periods/freeze_providers.dart';
import 'package:sielto/features/periods/freeze_ui.dart';
import 'package:sielto/features/periods/period_choice.dart';
import 'package:sielto/features/space/budget_ledger.dart';
import 'package:sielto/features/space/period_ledger.dart';
import 'package:sielto/features/space/space_ledger.dart';

/// Without [paymentId] it creates a record.
Future<void> openPaymentForm(
  BuildContext context, {
  String? paymentId,
  CalendarDate? date,
  PaymentDraft? draft,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (BuildContext _) =>
        PaymentFormPage(paymentId: paymentId, initialDate: date, draft: draft),
  ),
);

/// Prefilled unsaved record, from "duplicate before/after".
@immutable
class PaymentDraft {
  const PaymentDraft({
    required this.title,
    required this.amount,
    required this.date,
    required this.expenseType,
    this.categoryId,
    this.notes,
  });

  /// Copies onto [date], without `group_recurring_id` and `is_paid`.
  factory PaymentDraft.from(Payment payment, CalendarDate date) => PaymentDraft(
    title: payment.title,
    amount: payment.amount,
    date: date,
    expenseType: payment.expenseType,
    categoryId: payment.categoryId,
    notes: payment.notes,
  );

  final String title;
  final Decimal amount;
  final CalendarDate date;
  final ExpenseType expenseType;
  final String? categoryId;
  final String? notes;
}

class PaymentFormPage extends ConsumerStatefulWidget {
  const PaymentFormPage({
    this.paymentId,
    this.initialDate,
    this.draft,
    super.key,
  });

  final String? paymentId;
  final CalendarDate? initialDate;
  final PaymentDraft? draft;

  @override
  ConsumerState<PaymentFormPage> createState() => _PaymentFormPageState();
}

class _PaymentFormPageState extends ConsumerState<PaymentFormPage> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  /// Text appended to a frozen record's note.
  final TextEditingController _addedNote = TextEditingController();

  CalendarDate? _date;
  ExpenseType _type = ExpenseType.variable;
  String? _categoryId;
  bool _isPaid = false;
  bool _isRecurring = false;
  RecurrenceInterval _interval = RecurrenceInterval.monthly;

  /// Null: open-ended, up to [recurrenceHorizonMonths].
  int? _occurrences = 12;

  Payment? _existing;
  bool _loaded = false;
  bool _saving = false;

  /// Frozen: only the category and an appended note are editable.
  FreezeState _freeze = FreezeState.open;

  bool get _isFrozen => _freeze == FreezeState.frozen;

  /// income-driven Spaces only.
  PeriodChoice _periodChoice = PeriodChoice.byDate;
  PeriodChoice _loadedPeriodChoice = PeriodChoice.byDate;

  /// Cycles around the form's date.
  PeriodPair get _periods =>
      periodsAround(ref.read(incomePeriodsProvider), _date!);

  /// Series length and this occurrence's position, loaded with the record.
  int _seriesLength = 0;
  int _seriesPosition = 0;

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
    final PaymentDraft? draft = widget.draft;
    final String? id = widget.paymentId;

    if (id != null) {
      final Payment? row = await ref
          .read(repositoriesProvider)
          .payments
          .byId(id);
      if (row != null) {
        _existing = row;
        _title.text = row.title;
        _amount.text = row.amount.toString();
        _notes.text = row.notes ?? '';
        _date = row.dueDate;
        _type = row.expenseType;
        _categoryId = row.categoryId;
        _isPaid = row.isPaid;
        _freeze = ref.read(freezeLookupProvider).of(row.budgetPeriodId);
        _periodChoice = choiceOf(
          row,
          periodsAround(ref.read(incomePeriodsProvider), row.dueDate),
        );
        _loadedPeriodChoice = _periodChoice;

        final String? group = row.groupRecurringId;
        if (group != null) {
          final List<Payment> series = await ref
              .read(repositoriesProvider)
              .payments
              .seriesOf(group);
          _seriesLength = series.length;
          _seriesPosition =
              series.indexWhere((Payment p) => p.id == row.id) + 1;
        }
      }
    } else if (draft != null) {
      _title.text = draft.title;
      _amount.text = draft.amount.toString();
      _notes.text = draft.notes ?? '';
      _date = draft.date;
      _type = draft.expenseType;
      _categoryId = draft.categoryId;
    }

    _date ??= widget.initialDate ?? ref.read(spaceClockProvider).today();
    if (mounted) setState(() => _loaded = true);
  }

  Decimal? get _parsedAmount {
    final Decimal? value = parseMoney(_amount.text);
    if (value == null || value < Decimal.zero) return null;
    return value;
  }

  /// Trimmed title and a non-negative amount. Zero is a dated to-do.
  bool get _isValid =>
      _title.text.trim().isNotEmpty && _parsedAmount != null && !_saving;

  /// Dates outside this range warn but do not block.
  bool get _dateLooksOdd {
    final CalendarDate? date = _date;
    if (date == null) return false;
    final SpaceClock clock = ref.read(spaceClockProvider);
    final CalendarDate created = clock.dateOf(
      ref.read(currentSpaceProvider)!.createdAt,
    );
    return date.isBefore(created.addMonths(-12 * 5)) ||
        date.isAfter(clock.today().addMonths(12 * 10));
  }

  /// income-driven only, not for a series, and only when the date is inside a
  /// boundary's uncertainty window.
  bool _showPeriodChoice(Space space) =>
      space.budgetMode == BudgetMode.incomeDriven &&
      !_isFrozen &&
      !_isRecurring &&
      _periods.next != null &&
      periodIsAmbiguousOn(ref.read(incomePeriodsProvider), _date!);

  Future<void> _pickDate() async {
    final CalendarDate current = _date ?? ref.read(spaceClockProvider).today();
    final CalendarDate? picked = await pickDate(context, current);
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final Decimal? amount = _parsedAmount;
    final CalendarDate? date = _date;
    if (amount == null || date == null) return;

    setState(() => _saving = true);
    try {
      if (_isFrozen) {
        await _saveFrozen();
        return;
      }
      final Repositories repos = ref.read(repositoriesProvider);
      final Space space = ref.read(currentSpaceProvider)!;
      final String? notes = _notes.text.trim().isEmpty
          ? null
          : _notes.text.trim();
      final Payment? existing = _existing;

      if (existing == null) {
        if (_isRecurring) {
          await repos.payments.createSeries(
            spaceId: space.id,
            title: _title.text,
            amount: amount,
            dates: recurrenceDates(
              start: date,
              interval: _interval,
              count: _occurrences,
            ),
            expenseType: _type,
            categoryId: _categoryId,
            notes: notes,
          );
        } else {
          final Payment created = await repos.payments.create(
            spaceId: space.id,
            title: _title.text,
            amount: amount,
            dueDate: date,
            expenseType: _type,
            categoryId: _categoryId,
            notes: notes,
            isPaid: _isPaid,
          );
          if (_periodChoice != PeriodChoice.byDate) {
            await _applyPeriodChoice(repos, created.id);
          }
        }
      } else {
        if (existing.expenseType == ExpenseType.mandatory &&
            !await confirmMandatory(context)) {
          return;
        }
        final SeriesScope scope = await _resolveScope(existing);
        // Date and paid status are this occurrence's own in every scope.
        Future<void> applyOwn() async {
          if (date == existing.dueDate && _isPaid == existing.isPaid) return;
          await repos.payments.update(
            existing.id,
            dueDate: Value<CalendarDate>(date),
            isPaid: Value<bool>(_isPaid),
          );
        }

        switch (scope) {
          case SeriesScope.thisOne:
            await repos.payments.update(
              existing.id,
              title: Value<String>(_title.text),
              amount: Value<Decimal>(amount),
              dueDate: Value<CalendarDate>(date),
              expenseType: Value<ExpenseType>(_type),
              categoryId: Value<String?>(_categoryId),
              notes: Value<String?>(notes),
              isPaid: Value<bool>(_isPaid),
            );
            if (_periodChoice != _loadedPeriodChoice) {
              await _applyPeriodChoice(repos, existing.id);
            }
          case SeriesScope.allFuture:
            // Each occurrence keeps its own date.
            await repos.payments.updateSeriesFrom(
              existing.groupRecurringId!,
              existing.dueDate,
              title: Value<String>(_title.text),
              amount: Value<Decimal>(amount),
              expenseType: Value<ExpenseType>(_type),
              categoryId: Value<String?>(_categoryId),
              notes: Value<String?>(notes),
            );
            await applyOwn();
          case SeriesScope.wholeSeries:
            await repos.payments.updateWholeSeries(
              existing.groupRecurringId!,
              title: Value<String>(_title.text),
              amount: Value<Decimal>(amount),
              expenseType: Value<ExpenseType>(_type),
              categoryId: Value<String?>(_categoryId),
              notes: Value<String?>(notes),
            );
            await applyOwn();
          case SeriesScope.cancelled:
            return;
        }
      }
      // The recompute binds the payment to its period.
      ref.invalidate(periodRefreshProvider);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// `byDate` writes the containing period back as `auto`.
  Future<void> _applyPeriodChoice(Repositories repos, String paymentId) async {
    final BudgetPeriod? target = _periods.forChoice(_periodChoice);
    if (target == null) return;
    await repos.payments.setPeriod(
      paymentId,
      target.id,
      assignment: _periodChoice == PeriodChoice.byDate
          ? PeriodAssignment.auto
          : PeriodAssignment.manual,
    );
  }

  /// A frozen period allows the title, the category and an appended note.
  Future<void> _saveFrozen() async {
    final Payment existing = _existing!;
    final String addition = _addedNote.text.trim();
    final Repositories repos = ref.read(repositoriesProvider);

    await repos.payments.update(
      existing.id,
      title: Value<String>(_title.text),
      categoryId: Value<String?>(_categoryId),
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
    if (mounted) Navigator.of(context).pop();
  }

  /// Deletes the whole series or from this occurrence on.
  Future<void> _deleteSeries() async {
    final Payment? existing = _existing;
    final String? group = existing?.groupRecurringId;
    if (existing == null || group == null) return;

    final SeriesScope scope = await askSeriesDeleteScope(context);
    if (scope == SeriesScope.cancelled || !mounted) return;
    if (existing.expenseType == ExpenseType.mandatory &&
        !await confirmMandatory(context)) {
      return;
    }
    if (!mounted) return;

    await guardWrite(context, () async {
      final Repositories repos = ref.read(repositoriesProvider);
      await repos.payments.deleteSeries(
        group,
        from: scope == SeriesScope.allFuture ? existing.dueDate : null,
      );
    });
    ref.invalidate(periodRefreshProvider);
    if (mounted) Navigator.of(context).pop();
  }

  /// Records in a series ask for the scope.
  Future<SeriesScope> _resolveScope(Payment payment) async {
    if (payment.groupRecurringId == null) return SeriesScope.thisOne;
    if (!mounted) return SeriesScope.cancelled;
    return askSeriesScope(context);
  }

  Future<void> _delete() async {
    final Payment? existing = _existing;
    if (existing == null) return;
    if (existing.expenseType == ExpenseType.mandatory &&
        !await confirmMandatory(context)) {
      return;
    }
    await ref.read(repositoriesProvider).payments.softDelete(existing.id);
    ref.invalidate(periodRefreshProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final Space space = ref.space;
    final SageColors sage = context.sage;
    final String locale = context.locale.toString();
    final MoneyFormat money = MoneyFormat(
      locale: locale,
      currencyCode: space.currencyCode,
    );

    if (!_loaded) {
      return const Scaffold(body: Center(child: LeafLoader()));
    }

    return Scaffold(
      backgroundColor: sage.surface,
      appBar: AppBar(
        title: Text(_existing == null ? tr('payment.add') : tr('payment.edit')),
        actions: <Widget>[
          // No delete in a frozen period.
          if (_existing != null && !_isFrozen)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: tr('common.delete'),
              onPressed: _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (!_isFrozen)
              _LivePreview(
                amount: _parsedAmount,
                date: _date,
                replacingId: _existing?.id,
                isRecurring: _isRecurring && _existing == null,
                occurrences: _occurrences,
                interval: _interval,
                money: money,
                periodChoice: _periodChoice,
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(SageSpace.formGutter),
                children: <Widget>[
                  if (_isFrozen) const FreezeNotice(),
                  if (_seriesLength > 1) ...<Widget>[
                    _SeriesNotice(
                      position: _seriesPosition,
                      length: _seriesLength,
                      onDeleteSeries: _isFrozen ? null : _deleteSeries,
                    ),
                    const SizedBox(height: SageSpace.md),
                  ],
                  LabelledField(
                    label: tr('payment.fieldTitle'),
                    child: TitleField(controller: _title, spaceId: space.id),
                  ),
                  const SizedBox(height: SageSpace.lg),
                  LabelledField(
                    label: tr('payment.fieldAmount'),
                    child: MoneyField(
                      controller: _amount,
                      symbol: money.symbol,
                      enabled: !_isFrozen,
                    ),
                  ),
                  const SizedBox(height: SageSpace.lg),
                  LabelledField(
                    label: tr('payment.fieldDate'),
                    child: DateField(
                      label: DateLabels(locale).dayMonth(_date!),
                      onTap: _isFrozen ? null : _pickDate,
                      warn: _dateLooksOdd,
                    ),
                  ),
                  if (_dateLooksOdd)
                    Padding(
                      padding: const EdgeInsets.only(top: SageSpace.xs),
                      child: Text(
                        tr('payment.dateOutOfRange'),
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: sage.warning),
                      ),
                    ),
                  const SizedBox(height: SageSpace.lg),
                  LabelledField(
                    label: tr('payment.fieldCategory'),
                    child: CategoryPickerField(
                      selectedId: _categoryId,
                      onChanged: (Category? category) => setState(() {
                        _categoryId = category?.id;
                        // The category sets the default type for new records only.
                        if (category != null) _type = category.expenseType;
                      }),
                    ),
                  ),
                  const SizedBox(height: SageSpace.lg),
                  LabelledField(
                    label: tr('payment.fieldType'),
                    child: SegmentedChoice<ExpenseType>(
                      values: ExpenseType.values,
                      selected: _type,
                      labelOf: (ExpenseType t) => tr('expenseType.${t.name}'),
                      onChanged: (ExpenseType t) => setState(() => _type = t),
                      enabled: !_isFrozen,
                    ),
                  ),
                  if (_showPeriodChoice(space)) ...<Widget>[
                    const SizedBox(height: SageSpace.lg),
                    LabelledField(
                      label: tr('payment.fieldPeriod'),
                      child: SegmentedChoice<PeriodChoice>(
                        values: PeriodChoice.values,
                        selected: _periodChoice,
                        labelOf: (PeriodChoice c) => switch (c) {
                          PeriodChoice.byDate => tr('payment.periodAuto'),
                          PeriodChoice.current => tr('payment.periodCurrent'),
                          PeriodChoice.next => tr('payment.periodNext'),
                        },
                        onChanged: (PeriodChoice c) =>
                            setState(() => _periodChoice = c),
                      ),
                    ),
                    const SizedBox(height: SageSpace.xs),
                    Text(
                      tr('payment.periodHint'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (_existing == null) ...<Widget>[
                    const SizedBox(height: SageSpace.lg),
                    _RecurrenceFields(
                      isRecurring: _isRecurring,
                      interval: _interval,
                      occurrences: _occurrences,
                      onRecurringChanged: (bool value) =>
                          setState(() => _isRecurring = value),
                      onIntervalChanged: (RecurrenceInterval value) =>
                          setState(() => _interval = value),
                      onOccurrencesChanged: (int? value) =>
                          setState(() => _occurrences = value),
                    ),
                  ],
                  const SizedBox(height: SageSpace.lg),
                  if (_isFrozen)
                    AppendNoteField(
                      existing: _existing?.notes,
                      controller: _addedNote,
                      notesLabel: tr('payment.fieldNotes'),
                    )
                  else
                    LabelledField(
                      label: tr('payment.fieldNotes'),
                      child: TextField(
                        controller: _notes,
                        maxLines: 3,
                        maxLength: 5000,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: tr('payment.notesHint'),
                        ),
                      ),
                    ),
                  SwitchListTile.adaptive(
                    value: _isPaid,
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('payment.markPaid')),
                    onChanged: _isFrozen
                        ? null
                        : (bool value) => setState(() => _isPaid = value),
                  ),
                  const SizedBox(height: SageSpace.lg),
                  FilledButton(
                    onPressed: _isValid ? _save : null,
                    child: Text(tr('common.save')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live preview of the draft, in memory. Walks Flow's ledger, the Budget fund
/// or the draft's income cycle.
class _LivePreview extends ConsumerWidget {
  const _LivePreview({
    required this.amount,
    required this.date,
    required this.replacingId,
    required this.isRecurring,
    required this.occurrences,
    required this.interval,
    required this.money,
    required this.periodChoice,
  });

  final Decimal? amount;
  final CalendarDate? date;
  final String? replacingId;
  final bool isRecurring;
  final int? occurrences;
  final RecurrenceInterval interval;
  final MoneyFormat money;

  final PeriodChoice periodChoice;

  /// The cycle of the draft's date. Null before any cycle exists or beyond the
  /// materialised periods.
  PeriodLedger? _ledgerForDraft(WidgetRef ref) {
    final CalendarDate? draftDate = date;
    if (draftDate == null) return null;

    final List<BudgetPeriod> periods = ref.watch(incomePeriodsProvider);
    final BudgetPeriod? target = periodsAround(
      periods,
      draftDate,
    ).forChoice(periodChoice);
    if (target == null) return null;

    final List<Payment>? payments = ref.watch(spacePaymentsProvider).value;
    final List<Income>? incomes = ref.watch(spaceIncomesProvider).value;
    final List<IncomeRecurrenceRule>? rules = ref
        .watch(incomeRulesProvider)
        .value;
    if (payments == null || incomes == null || rules == null) return null;

    return buildPeriodLedger(
      period: target,
      payments: payments,
      incomes: incomes,
      anchorRuleIds: <String>{
        for (final IncomeRecurrenceRule r in rules)
          if (r.isAnchor) r.id,
      },
      today: ref.watch(spaceClockProvider).today(),
    );
  }

  /// "12.08 – 10.09", or null without cycles.
  String? _periodLabel(WidgetRef ref, BuildContext context) {
    final CalendarDate? draftDate = date;
    if (draftDate == null) return null;
    if (ref.watch(currentSpaceProvider)?.budgetMode !=
        BudgetMode.incomeDriven) {
      return null;
    }

    final BudgetPeriod? target = periodsAround(
      ref.watch(incomePeriodsProvider),
      draftDate,
    ).forChoice(periodChoice);
    final CalendarDate? end = target?.endDate;
    if (target == null || end == null) return null;

    final DateLabels dates = DateLabels(context.locale.toString());
    return '${dates.short(target.startDate)} – ${dates.short(end)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;

    final Decimal? available;
    final List<LedgerEntry> existing;
    String label = tr('dashboard.freeMoney');
    // A Budget Space without a fund only counts what it spends.
    bool spentOnly = false;
    final BudgetMode? mode = ref.watch(currentSpaceProvider)?.budgetMode;
    if (mode == BudgetMode.incomeDriven) {
      // The cycle of the draft's date, not the one on screen.
      final PeriodLedger? period = _ledgerForDraft(ref);
      if (period == null) return const SizedBox.shrink();
      available = period.anchorAmount;
      existing = period.entries;
    } else if (mode == BudgetMode.budget) {
      final BudgetLedger? budget = ref.watch(budgetLedgerProvider).value;
      if (budget == null) return const SizedBox.shrink();
      spentOnly = !budget.hasFund;
      label = tr(spentOnly ? 'budget.spent' : 'budget.remaining');
      available = budget.available;
      existing = budget.entries;
    } else {
      final FlowLedger? flow = ref.watch(flowLedgerProvider).value;
      if (flow == null) return const SizedBox.shrink();
      available = flow.available;
      existing = flow.entries;
    }
    // No preview when the salary has no amount.
    if (available == null) return const SizedBox.shrink();

    final Decimal? draftAmount = amount;
    final CalendarDate? draftDate = date;

    final List<LedgerEntry> draft = <LedgerEntry>[
      if (draftAmount != null && draftDate != null)
        for (final CalendarDate d
            in isRecurring
                ? recurrenceDates(
                    start: draftDate,
                    interval: interval,
                    count: occurrences,
                  )
                : <CalendarDate>[draftDate])
          LedgerEntry(
            id: 'draft:${d.toIso()}',
            date: d,
            amount: draftAmount,
            isIncome: false,
            // Last within its day.
            sortOrder: 1 << 30,
          ),
    ];

    final LedgerRun before = previewRun(
      available: available,
      entries: existing,
      draft: const <LedgerEntry>[],
      replacingId: replacingId,
    );
    final LedgerRun after = previewRun(
      available: available,
      entries: existing,
      draft: draft,
      replacingId: replacingId,
    );

    // Budget entries are all expenses.
    Decimal spent(LedgerRun run) => run.available - run.finalBalance;
    final Decimal? beforeFree = spentOnly ? spent(before) : before.freeCash;
    final Decimal? afterFree = spentOnly ? spent(after) : after.freeCash;
    final Color afterColor = afterFree == null ? sage.danger : sage.ink;

    final String? periodLabel = _periodLabel(ref, context);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        SageSpace.formGutter,
        SageSpace.md,
        SageSpace.formGutter,
        0,
      ),
      padding: const EdgeInsets.all(SageSpace.md),
      decoration: BoxDecoration(
        color: sage.accentTint,
        borderRadius: BorderRadius.circular(SageRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            periodLabel == null ? label : '$label ($periodLabel)',
            style: text.bodySmall?.copyWith(color: sage.inkSecondary),
          ),
          const SizedBox(height: SageSpace.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Text(
                beforeFree == null
                    ? tr('dashboard.notCovered')
                    : money.format(beforeFree),
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
                  afterFree == null
                      ? tr('dashboard.notCovered')
                      : money.format(afterFree),
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium?.copyWith(color: afterColor),
                ),
              ),
              if (draftAmount != null &&
                  draftAmount > Decimal.zero) ...<Widget>[
                const SizedBox(width: SageSpace.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: sage.dangerTint,
                    borderRadius: BorderRadius.circular(SageRadius.pill),
                  ),
                  child: Text(
                    '−${money.format(draftAmount)}',
                    style: text.labelSmall?.copyWith(color: sage.danger),
                  ),
                ),
              ],
            ],
          ),
          if (isRecurring && draft.length > 1) ...<Widget>[
            const SizedBox(height: SageSpace.xs),
            Text(
              tr(
                'payment.recurringPreview',
                namedArgs: <String, String>{
                  'now': money.format(draftAmount!),
                  'total': money.format(
                    draftAmount * Decimal.fromInt(draft.length),
                  ),
                  'count': '${draft.length}',
                },
              ),
              style: text.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// Marks a payment as part of a series and offers deleting the series.
class _SeriesNotice extends StatelessWidget {
  const _SeriesNotice({
    required this.position,
    required this.length,
    required this.onDeleteSeries,
  });

  final int position;
  final int length;

  /// Null in a frozen period.
  final VoidCallback? onDeleteSeries;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SageSpace.md),
      decoration: BoxDecoration(
        color: sage.canvas,
        borderRadius: BorderRadius.circular(SageRadius.button),
        border: Border.all(color: sage.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.repeat, size: 18, color: sage.inkLabel),
              const SizedBox(width: SageSpace.sm),
              Expanded(
                child: Text(
                  tr(
                    'payment.seriesPosition',
                    namedArgs: <String, String>{
                      'position': '$position',
                      'count': '$length',
                    },
                  ),
                  style: text.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: SageSpace.xs),
          Text(
            tr('payment.seriesHint'),
            style: text.bodySmall?.copyWith(color: sage.inkSecondary),
          ),
          if (onDeleteSeries != null) ...<Widget>[
            const SizedBox(height: SageSpace.xs),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: onDeleteSeries,
                style: TextButton.styleFrom(foregroundColor: sage.danger),
                child: Text(tr('payment.deleteSeries')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One-off or repeating, and how many times.
class _RecurrenceFields extends StatelessWidget {
  const _RecurrenceFields({
    required this.isRecurring,
    required this.interval,
    required this.occurrences,
    required this.onRecurringChanged,
    required this.onIntervalChanged,
    required this.onOccurrencesChanged,
  });

  final bool isRecurring;
  final RecurrenceInterval interval;
  final int? occurrences;
  final ValueChanged<bool> onRecurringChanged;
  final ValueChanged<RecurrenceInterval> onIntervalChanged;
  final ValueChanged<int?> onOccurrencesChanged;

  /// Null: indefinitely.
  static const List<int?> _choices = <int?>[3, 6, 12, 24, null];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      SegmentedChoice<bool>(
        values: const <bool>[false, true],
        selected: isRecurring,
        labelOf: (bool value) =>
            value ? tr('payment.recurring') : tr('payment.oneOff'),
        onChanged: onRecurringChanged,
      ),
      if (isRecurring) ...<Widget>[
        const SizedBox(height: SageSpace.md),
        SegmentedChoice<RecurrenceInterval>(
          values: RecurrenceInterval.values,
          selected: interval,
          labelOf: (RecurrenceInterval value) => tr('recurrence.${value.name}'),
          onChanged: onIntervalChanged,
        ),
        const SizedBox(height: SageSpace.md),
        Wrap(
          spacing: SageSpace.sm,
          children: <Widget>[
            for (final int? choice in _choices)
              ChoiceChip(
                selected: occurrences == choice,
                label: Text(
                  choice == null
                      ? tr('recurrence.indefinitely')
                      : plural('recurrence.times', choice),
                ),
                onSelected: (bool _) => onOccurrencesChanged(choice),
              ),
          ],
        ),
      ],
    ],
  );
}
