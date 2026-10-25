import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart' show HapticFeedback, HardwareKeyboard;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/payment_repository.dart';
import 'package:sielto/core/format/context_format.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/settings/local_settings.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/bulk_button.dart';
import 'package:sielto/core/ui/detail_host.dart';
import 'package:sielto/core/ui/form_fields.dart';
import 'package:sielto/core/ui/layout.dart';
import 'package:sielto/core/ui/leaf_loader.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/dashboard/balance_sheet.dart';
import 'package:sielto/features/dashboard/period_selector.dart';
import 'package:sielto/features/feed/feed_columns.dart';
import 'package:sielto/features/feed/feed_filter.dart';
import 'package:sielto/features/feed/feed_menu.dart';
import 'package:sielto/features/feed/feed_model.dart';
import 'package:sielto/features/feed/feed_reorder.dart';
import 'package:sielto/features/feed/feed_row.dart';
import 'package:sielto/features/feed/feed_selection.dart';
import 'package:sielto/features/feed/feed_window.dart';
import 'package:sielto/features/feed/record_actions.dart';
import 'package:sielto/features/overdue/overdue.dart';
import 'package:sielto/features/periods/freeze_providers.dart';
import 'package:sielto/features/periods/freeze_ui.dart';
import 'package:sielto/features/periods/period_service.dart';
import 'package:sielto/features/shell/app_header.dart';
import 'package:sielto/features/space/budget_ledger.dart';
import 'package:sielto/features/space/period_ledger.dart';
import 'package:sielto/features/space/space_ledger.dart';

/// Chronological list of payments and incomes.
class FeedPage extends ConsumerStatefulWidget {
  const FeedPage({super.key});

  @override
  ConsumerState<FeedPage> createState() => _FeedPageState();
}

/// Fixed extents map scroll offsets to rows without measuring.
const double _headerExtent = 40;
const double _cutoffExtent = 34;

class _FeedPageState extends ConsumerState<FeedPage> {
  final ScrollController _scroll = ScrollController();

  /// Last built list, for the scroll listener and the arrows.
  List<FeedItem> _items = const <FeedItem>[];

  List<FeedRecord> _records = const <FeedRecord>[];

  /// Offset of each item in [_items], plus the total at the end.
  List<double> _starts = const <double>[0];

  /// Date of the last header at or before each item in [_items].
  List<CalendarDate?> _headers = const <CalendarDate?>[];

  bool _edgeCheckQueued = false;

  /// Whether the bulk button was pressed during this selection.
  bool _bulkSeen = false;

  /// Order just dropped, shown until the query reads it back.
  Map<String, int>? _dropped;

  /// True from widening the window until the wider list is built.
  bool _extending = false;

  /// Top item before older rows were added above, to keep the view in place.
  FeedItem? _keptTop;

  /// The Space the list was last placed in: its period, or today.
  String? _placedIn;

  /// The [feedGrowth] behind the current offsets.
  double? _grow;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_extendOnEdge);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_extendOnEdge)
      ..dispose();
    super.dispose();
  }

  /// Widens the window at either end and, while the user scrolls, syncs the
  /// selected period.
  void _extendOnEdge() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.userScrollDirection != ScrollDirection.idle) {
      _syncPeriodToScroll();
    }
    final ScrollPosition position = _scroll.position;
    const double margin = 400;
    if (_extending) return;
    final FeedWindow window = ref.read(feedWindowProvider);
    if (position.pixels <= position.minScrollExtent + margin &&
        _anyRecord((CalendarDate d) => d.isBefore(window.from))) {
      _extending = true;
      _keptTop = _items.firstOrNull;
      ref.read(feedWindowProvider.notifier).extendBackwards();
    } else if (position.pixels >= position.maxScrollExtent - margin) {
      if (_anyRecord((CalendarDate d) => d.isAfter(window.to))) {
        _extending = true;
        ref.read(feedWindowProvider.notifier).extendForwards();
      } else if (ref.read(currentSpaceProvider)?.budgetMode ==
              BudgetMode.incomeDriven &&
          window.to.isBefore(
            ref
                .read(spaceClockProvider)
                .today()
                .addMonths(PeriodService.maxReachMonths),
          )) {
        // No records beyond: request more periods.
        ref
            .read(periodReachProvider.notifier)
            .reach(window.to.addMonths(PeriodService.horizonStepMonths));
      }
    }
  }

  bool _anyRecord(bool Function(CalendarDate) test) =>
      (ref.read(spacePaymentsProvider).value ?? const <Payment>[]).any(
        (Payment p) => test(p.dueDate),
      ) ||
      (ref.read(spaceIncomesProvider).value ?? const <Income>[]).any(
        (Income i) => test(i.expectedDate),
      );

  void _afterExtend(List<FeedItem> items) {
    _extending = false;
    final FeedItem? kept = _keptTop;
    _keptTop = null;
    if (kept == null) return;
    // Keeps the view on the same item.
    final double? y = _offsetOf((FeedItem i) => _sameItem(i, kept));
    if (y == null || y == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.pixels + y);
    });
  }

  static bool _sameItem(FeedItem a, FeedItem b) => switch ((a, b)) {
    (final FeedHeader x, final FeedHeader y) => x.date == y.date,
    (final FeedRow x, final FeedRow y) => x.record.id == y.record.id,
    (final FeedCutoff x, final FeedCutoff y) => x.entryId == y.entryId,
    _ => false,
  };

  /// Within the last built [_items].
  double? _offsetOf(bool Function(FeedItem) test) {
    final int i = _items.indexWhere(test);
    return i < 0 ? null : _starts[i];
  }

  void _measure(List<FeedItem> items, double rowHeight, double grow) {
    final List<double> starts = <double>[0];
    final List<CalendarDate?> headers = <CalendarDate?>[];
    CalendarDate? header;
    for (final FeedItem item in items) {
      if (item is FeedHeader) header = item.date;
      headers.add(header);
      starts.add(starts.last + _extentOf(item, rowHeight, grow));
    }
    _starts = starts;
    _headers = headers;
  }

  static double _extentOf(FeedItem item, double rowHeight, double grow) =>
      switch (item) {
        FeedHeader() => _headerExtent * grow,
        FeedCutoff() => _cutoffExtent * grow,
        FeedRow() => rowHeight,
      };

  /// Room under the last row so the last period can reach the top.
  double _bottomSlack(double viewport, bool byPeriod) {
    const double floor = 96;
    final BudgetPeriod? last = ref.read(incomePeriodsProvider).lastOrNull;
    if (!byPeriod || last == null) return floor;
    final double? start = _offsetOf(
      (FeedItem i) => i is FeedHeader && !i.date.isBefore(last.startDate),
    );
    if (start == null) return floor;
    return math.max(floor, viewport - (_starts.last - start));
  }

  @override
  Widget build(BuildContext context) {
    final Space space = ref.space;
    final AsyncValue<Map<String, Category>> categories = ref.watch(
      categoryIndexProvider,
    );
    final bool table = ShellLayout.of(context) != ShellMode.phone;
    // The table has one row height.
    final FeedDensity density = table
        ? FeedDensity.compact
        : ref.watch(feedDensityProvider);
    final MoneyFormat money = context.moneyIn(space.currencyCode);
    final DateLabels dates = context.dates;

    final _FeedSource? source = _source(space);
    if (source == null) {
      return Scaffold(
        backgroundColor: context.sage.surface,
        appBar: AppHeader(title: tr('nav.feed')),
        body: const Center(child: LeafLoader()),
      );
    }

    final FeedFilter filter = ref.watch(feedFilterProvider);
    final Set<String> selection = ref.watch(feedSelectionProvider);
    if (selection.isEmpty) _bulkSeen = false;
    _records = source.records;
    _items = buildFeedItems(
      records: filter.isActive
          ? source.records.where(filter.matches).toList()
          : source.records,
      orderMode: space.feedOrderMode,
      coverage: source.coverage,
      moneyEndsAt: source.moneyEndsAt,
      today: filter.isActive ? null : source.today,
      emptyPeriodStarts: filter.isActive || !source.byPeriod
          ? const <CalendarDate>[]
          : _emptyPeriodStarts(source.records),
    );
    final List<FeedItem> items = _items;
    final double grow = feedGrowth(context);
    _measure(
      items,
      rowHeightFor(context, density) +
          (hasRowBorder(density, table: table) ? rowBorder : 0),
      grow,
    );
    // Every extent scales by the same factor, so the same day stays on top.
    if (_grow case final double was when was != grow && _scroll.hasClients) {
      final double offset = _scroll.position.pixels * grow / was;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(offset);
      });
    }
    _grow = grow;
    if (_extending) _afterExtend(items);
    // Checks the edges after layout: a list that fits never scrolls.
    if (!_edgeCheckQueued) {
      _edgeCheckQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _edgeCheckQueued = false;
        if (mounted) _extendOnEdge();
      });
    }
    if (_placedIn != space.id && items.isNotEmpty) {
      _placedIn = space.id;
      final BudgetPeriod? selected = ref.read(selectedPeriodProvider);
      if (source.byPeriod && selected != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollToPeriod(selected, animate: false),
        );
      } else if (!filter.isActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final double? y = _offsetOf(
            (FeedItem i) => i is FeedHeader && !i.date.isBefore(source.today),
          );
          if (y != null && mounted && _scroll.hasClients) {
            // maxScrollExtent is an estimate until every row is laid out.
            _scroll.jumpTo(y);
          }
        });
      }
    }
    final bool atBottom = controlsAtBottom(context, ref, ControlsScreen.feed);
    final Widget selector = PeriodSelector(
      onJump: (BudgetPeriod p) => _scrollToPeriod(p),
      swipe: !atBottom,
    );

    final Widget page = Scaffold(
      backgroundColor: context.sage.surface,
      appBar: AppHeader(
        title: tr('nav.feed'),
        trailing: table
            ? null
            : <Widget>[
                Padding(
                  padding: const EdgeInsets.only(right: SageSpace.sm),
                  child: Badge(
                    isLabelVisible: filter.isActive,
                    backgroundColor: context.sage.accentStrong,
                    smallSize: 8,
                    child: SoftIconButton(
                      size: 44,
                      icon: Icons.search,
                      tooltip: tr('feed.filter.title'),
                      onTap: () => showFeedFilter(context),
                    ),
                  ),
                ),
              ],
        bottom: table
            ? null
            : _FeedTotals(
                source: source,
                money: money,
                onBalanceTap: space.budgetMode == BudgetMode.flow
                    ? () => showBalanceSheet(
                        context,
                        ref,
                        space: space,
                        money: money,
                      )
                    : null,
                hasOverdue: !ref.watch(overduePaymentsProvider).isEmpty,
                selector:
                    source.byPeriod &&
                        !atBottom &&
                        ShellLayout.of(context) == ShellMode.phone
                    ? selector
                    : null,
              ),
      ),
      bottomNavigationBar: source.byPeriod && atBottom
          ? SafeArea(top: false, child: selector)
          : null,
      floatingActionButton: selection.isNotEmpty
          ? BulkActionsButton(
              pulse: !_bulkSeen,
              tooltip: tr('feed.bulk.title'),
              onPressed: () {
                setState(() => _bulkSeen = true);
                showBulkActions(
                  context,
                  ref,
                  records: <FeedRecord>[
                    for (final FeedRecord r in source.records)
                      if (selection.contains(r.id)) r,
                  ],
                );
              },
            )
          : table
          ? null
          : FloatingActionButton(
              tooltip: tr('common.add'),
              backgroundColor: context.sage.accent,
              foregroundColor: context.sage.accentOn,
              shape: const CircleBorder(),
              onPressed: () => showQuickAddMenu(
                context,
                ref,
                date: source.today,
                title: tr('feed.today'),
              ),
              child: const Icon(Icons.add),
            ),
      body: FocusTraversalGroup(
        child: Readable(
          maxWidth: ShellLayout.of(context) == ShellMode.phone
              ? Readable.feed
              : Readable.feedTable,
          child: Column(
            children: <Widget>[
              if (table)
                _TableToolbar(
                  source: source,
                  money: money,
                  filtered: filter.isActive,
                  onBalanceTap: space.budgetMode == BudgetMode.flow
                      ? () => showBalanceSheet(
                          context,
                          ref,
                          space: space,
                          money: money,
                        )
                      : null,
                  figures:
                      ShellLayout.of(context) != ShellMode.columns ||
                      ref.watch(columnsLayoutProvider).dashboardCollapsed,
                  onSearch: () => ref
                      .read(feedFilterOpenProvider.notifier)
                      .set(open: !ref.read(feedFilterOpenProvider)),
                  onAdd: () => showQuickAddMenu(
                    context,
                    ref,
                    date: source.today,
                    title: tr('feed.today'),
                  ),
                ),
              if (selection.isNotEmpty)
                Semantics(
                  container: true,
                  liveRegion: true,
                  child: _SelectionBar(
                    count: selection.length,
                    onClose: ref.read(feedSelectionProvider.notifier).clear,
                  ),
                ),
              if (table)
                _Unfold(
                  child: ref.watch(feedFilterOpenProvider)
                      // At most a third of the window, so the table keeps
                      // room.
                      ? ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.sizeOf(context).height / 3,
                          ),
                          child: SingleChildScrollView(
                            child: FeedFilterPanel(
                              shown: _allMatches(filter),
                              money: money,
                            ),
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              if (filter.isActive &&
                  !(table && ref.watch(feedFilterOpenProvider)))
                Semantics(
                  container: true,
                  child: FeedFilterBar(
                    shown: _allMatches(filter),
                    money: money,
                  ),
                ),
              if (!table &&
                  !ref.watch(tickHintSeenProvider) &&
                  selection.isEmpty &&
                  items.any((FeedItem i) => i is FeedRow))
                Semantics(
                  container: true,
                  child: _TickHint(
                    onClose: ref.read(tickHintSeenProvider.notifier).dismiss,
                  ),
                ),
              Expanded(
                child: _tableCard(
                  table: table,
                  header: items.isNotEmpty,
                  fitWidth: (FeedColumn c) => _fitWidth(
                    c,
                    categories: categories.value ?? const <String, Category>{},
                    leftAfter: source.leftAfter,
                    money: money,
                    dates: dates,
                  ),
                  child: items.isEmpty
                      ? EmptyState(
                          message: tr(
                            filter.isActive
                                ? 'feed.filter.nothing'
                                : '${desktopInput ? 'feed.emptyDesktop' : 'feed.empty'}'
                                      '${space.budgetMode == BudgetMode.budget ? 'Budget' : ''}',
                          ),
                        )
                      : LayoutBuilder(
                          builder: (BuildContext context, BoxConstraints box) =>
                              FocusTraversalGroup(
                                child: ReorderableListView.builder(
                                  scrollController: _scroll,
                                  buildDefaultDragHandles: false,
                                  padding: EdgeInsets.only(
                                    bottom: _bottomSlack(
                                      box.maxHeight,
                                      source.byPeriod,
                                    ),
                                  ),
                                  itemCount: items.length,
                                  itemBuilder:
                                      (
                                        BuildContext context,
                                        int index,
                                      ) => _buildItem(
                                        context,
                                        items[index],
                                        index: index,
                                        density: density,
                                        money: money,
                                        dates: dates,
                                        today: source.today,
                                        categories:
                                            categories.value ??
                                            const <String, Category>{},
                                        freeze: ref.watch(freezeLookupProvider),
                                        beyondDeadline: source.beyondDeadline,
                                        canReorder:
                                            !filter.isActive &&
                                            selection.isEmpty,
                                        selection: selection,
                                        leftAfter: table
                                            ? source.leftAfter
                                            : null,
                                      ),
                                  onReorderStart: (int index) =>
                                      HapticFeedback.mediumImpact(),
                                  onReorderItem: (int oldIndex, int newIndex) =>
                                      _onReorder(
                                        items: items,
                                        oldIndex: oldIndex,
                                        insertAt: newIndex,
                                        orderMode: space.feedOrderMode,
                                      ),
                                ),
                              ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!table) return page;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final ThemeData theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            snackBarTheme: theme.snackBarTheme.copyWith(
              width:
                  math.min(box.maxWidth, Readable.feedTable) - 2 * SageSpace.md,
            ),
          ),
          child: ScaffoldMessenger(child: page),
        );
      },
    );
  }

  /// The table sits on a card with its headings and a hint line.
  /// The widest entry of [c] among the loaded rows, or its heading.
  double _fitWidth(
    FeedColumn c, {
    required Map<String, Category> categories,
    required Map<String, Decimal>? leftAfter,
    required MoneyFormat money,
    required DateLabels dates,
  }) {
    final TextStyle heading = Theme.of(context).textTheme.labelSmall!
        .copyWith(fontWeight: FontWeight.w700);
    double widest = textWidth(
      context,
      tr('feed.table.${c.name}').toUpperCase(),
      heading,
    );
    for (final FeedRecord r in _records) {
      final Decimal? left = leftAfter?[r.id];
      final (String value, TextStyle style) = tableCellText(
        context,
        c,
        record: r,
        category: r.categoryId == null ? null : categories[r.categoryId],
        date: dates.dayMonthShort(r.date),
        leftAfter: left == null ? null : money.format(left),
        amount: feedAmountLabel(r, money),
      );
      widest = math.max(widest, textWidth(context, value, style));
    }
    // The cell's padding, and a pixel against rounding.
    return widest + 24 + 1;
  }

  Widget _tableCard({
    required bool table,
    required bool header,
    required double Function(FeedColumn c) fitWidth,
    required Widget child,
  }) {
    if (!table) return child;
    final SageColors sage = context.sage;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        SageSpace.md,
        0,
        SageSpace.md,
        SageSpace.md,
      ),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: sage.card,
        borderRadius: BorderRadius.circular(SageRadius.card),
        border: Border.all(color: sage.border),
      ),
      // A card too short for rows drops the hint line.
      child: LayoutBuilder(
        builder: (BuildContext _, BoxConstraints box) => Column(
          children: <Widget>[
            if (header) FeedTableHeader(fitWidth: fitWidth),
            Expanded(child: child),
            if (desktopInput && header && box.maxHeight > 200)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: SageSpace.md,
                  vertical: SageSpace.sm,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: sage.hairline)),
                ),
                child: Text(
                  tr('feed.table.hint'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: sage.inkLabel),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Every record the filter matches, outside the render window too.
  List<FeedRecord> _allMatches(FeedFilter filter) => <FeedRecord>[
    for (final Payment p
        in ref.read(spacePaymentsProvider).value ?? const <Payment>[])
      if (filter.matches(FeedRecord.fromPayment(p))) FeedRecord.fromPayment(p),
    for (final Income i
        in ref.read(spaceIncomesProvider).value ?? const <Income>[])
      if (filter.matches(FeedRecord.fromIncome(i))) FeedRecord.fromIncome(i),
  ];

  /// The list and its figures. One continuous list in every mode; only the
  /// figures follow the selected period.
  _FeedSource? _source(Space space) {
    final List<Payment>? payments = ref.watch(spacePaymentsProvider).value;
    final List<Income>? incomes = ref.watch(spaceIncomesProvider).value;
    if (payments == null || incomes == null) return null;
    // Right after a Space switch the lists still hold the previous Space.
    if (payments.firstOrNull?.spaceId case final String id
        when id != space.id) {
      return null;
    }
    if (incomes.firstOrNull?.spaceId case final String id when id != space.id) {
      return null;
    }

    final FeedWindow window = ref.watch(feedWindowProvider);
    final List<FeedRecord> records = <FeedRecord>[
      for (final Payment p in payments)
        if (window.contains(p.dueDate)) FeedRecord.fromPayment(p),
      for (final Income i in incomes)
        if (window.contains(i.expectedDate)) FeedRecord.fromIncome(i),
    ];
    _applyDropped(records);

    if (space.budgetMode == BudgetMode.incomeDriven) {
      final List<PeriodLedger> ledgers =
          ref.watch(periodLedgersProvider).value ?? const <PeriodLedger>[];
      final Map<String, bool> coverage = <String, bool>{};
      final Map<String, bool> endsAt = <String, bool>{};
      final Map<String, Decimal> left = <String, Decimal>{};
      for (final PeriodLedger ledger in ledgers) {
        coverage.addAll(ledger.coverageByEntry);
        left.addAll(ledger.balanceByEntry);
        final ({String entryId, bool below})? end = ledger.moneyEndsAt;
        if (end != null) endsAt[end.entryId] = end.below;
      }

      // No periods before the first regular income.
      final PeriodLedger? selected = ref.watch(periodLedgerProvider).value;
      if (selected == null) {
        return _FeedSource(
          records: records,
          today: ref.watch(spaceClockProvider).today(),
          coverage: coverage,
          moneyEndsAt: endsAt,
          available: Decimal.zero,
          freeCash: null,
          paid: Decimal.zero,
          remaining: Decimal.zero,
          byPeriod: false,
          mode: space.budgetMode,
          hasIncome: false,
        );
      }

      return _FeedSource(
        records: records,
        today: selected.today,
        coverage: coverage,
        leftAfter: left,
        moneyEndsAt: endsAt,
        available: selected.anchorAmount,
        freeCash: selected.freeCash,
        paid: selected.totalPaid,
        remaining: selected.totalRemaining,
        byPeriod: true,
        mode: space.budgetMode,
        hasIncome: selected.hasIncome,
      );
    }

    final SpaceLedger? ledger = space.budgetMode == BudgetMode.budget
        ? ref.watch(budgetLedgerProvider).value
        : ref.watch(flowLedgerProvider).value;
    if (ledger == null) return null;
    final BudgetLedger? budget = ledger is BudgetLedger ? ledger : null;
    final ({String entryId, bool below})? end = ledger.moneyEndsAt;
    return _FeedSource(
      records: records,
      today: ledger.today,
      coverage: ledger.coverageByEntry,
      leftAfter: ledger.balanceByEntry,
      moneyEndsAt: <String, bool>{if (end != null) end.entryId: end.below},
      available: ledger.available,
      // Without a fund the Budget figure is what was spent.
      freeCash: budget?.hasFund ?? true ? ledger.freeCash : ledger.available,
      paid: ledger.totalPaid,
      remaining: ledger.totalRemaining,
      byPeriod: false,
      mode: space.budgetMode,
      beyondDeadline: budget?.beyondDeadline ?? const <String>{},
    );
  }

  /// Drops the overlay once the records match it.
  void _applyDropped(List<FeedRecord> records) {
    final Map<String, int>? dropped = _dropped;
    if (dropped == null) return;

    bool settled = true;
    for (int i = 0; i < records.length; i++) {
      final int? order = dropped[records[i].id];
      if (order == null || records[i].sortOrder == order) continue;
      records[i] = records[i].withSortOrder(order);
      settled = false;
    }
    if (settled) _dropped = null;
  }

  /// Periods in the render window with no entries, so the selector can
  /// still scroll to them.
  List<CalendarDate> _emptyPeriodStarts(List<FeedRecord> records) {
    final FeedWindow window = ref.watch(feedWindowProvider);
    return <CalendarDate>[
      for (final BudgetPeriod p in ref.watch(incomePeriodsProvider))
        if (window.contains(p.startDate) &&
            !records.any(
              (FeedRecord r) =>
                  !r.date.isBefore(p.startDate) &&
                  (p.endDate == null || !r.date.isAfter(p.endDate!)),
            ))
          p.startDate,
    ];
  }

  /// Selects the period of the top visible day.
  void _syncPeriodToScroll() {
    final List<BudgetPeriod> periods = ref.read(incomePeriodsProvider);
    if (periods.isEmpty || !_scroll.hasClients) return;

    final CalendarDate? top = _topVisibleDate();
    if (top == null) return;

    for (final BudgetPeriod p in periods) {
      final CalendarDate? end = p.endDate;
      if (p.startDate.isAfter(top)) continue;
      if (end != null && end.isBefore(top)) continue;
      if (ref.read(selectedPeriodIdProvider) != p.id) {
        ref.read(selectedPeriodIdProvider.notifier).select(p.id);
      }
      return;
    }
  }

  /// First row at or below the top of the viewport, from the fixed extents.
  /// Binary search over [_starts].
  CalendarDate? _topVisibleDate() {
    final List<FeedItem> items = _items;
    if (items.isEmpty) return null;
    final double offset = _scroll.position.pixels;
    int lo = 0;
    int hi = items.length - 1;
    // First item whose end is below the offset.
    while (lo < hi) {
      final int mid = (lo + hi) ~/ 2;
      if (_starts[mid + 1] > offset) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return _headers[lo] ?? _firstDateOf(items);
  }

  CalendarDate? _firstDateOf(List<FeedItem> items) {
    for (final FeedItem item in items) {
      if (item is FeedHeader) return item.date;
    }
    return null;
  }

  /// Scrolls to where [period] begins.
  void _scrollToPeriod(BudgetPeriod period, {bool animate = true}) {
    if (!_scroll.hasClients) return;
    final FeedWindow window = ref.read(feedWindowProvider);
    if (!window.contains(period.startDate)) {
      final FeedWindowController widen = ref.read(feedWindowProvider.notifier);
      period.startDate.isBefore(window.from)
          ? widen.extendBackwards()
          : widen.extendForwards();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToPeriod(period, animate: false);
      });
      return;
    }
    final double? y = _offsetOf(
      (FeedItem i) => i is FeedHeader && !i.date.isBefore(period.startDate),
    );
    if (y == null) return;
    final double target = math.max(y, _scroll.position.minScrollExtent);
    if (!animate || MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
      return;
    }
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildItem(
    BuildContext context,
    FeedItem item, {
    required int index,
    required FeedDensity density,
    required MoneyFormat money,
    required DateLabels dates,
    required CalendarDate today,
    required Map<String, Category> categories,
    required FreezeLookup freeze,
    required Set<String> beyondDeadline,
    required bool canReorder,
    required Set<String> selection,
    required Map<String, Decimal>? leftAfter,
  }) {
    switch (item) {
      case FeedHeader():
        return _DayHeader(
          key: ValueKey<String>(item.key),
          header: item,
          today: today,
          dates: dates,
          band: leftAfter != null,
          empty: index + 1 >= _items.length || _items[index + 1] is FeedHeader,
        );
      case FeedCutoff():
        return _CutoffLine(key: ValueKey<String>(item.key), item: item);
      case FeedRow():
        final FeedRecord record = item.record;
        final Decimal? left = leftAfter?[record.id];
        return FeedRowTile(
          key: ValueKey<String>(item.key),
          record: record,
          table: leftAfter == null
              ? null
              : FeedTableCells(
                  date: dates.dayMonthShort(record.date),
                  leftAfter: left == null ? null : money.format(left),
                  short: left != null && left < Decimal.zero,
                  layout: ref.watch(feedColumnsProvider),
                ),
          isCovered: item.isCovered,
          density: density,
          money: money,
          category: record.categoryId == null
              ? null
              : categories[record.categoryId],
          // Ctrl-click selects, as a long press does.
          onTap: () =>
              selection.isEmpty && !HardwareKeyboard.instance.isControlPressed
              ? editRecord(context, record)
              : ref.read(feedSelectionProvider.notifier).toggle(record.id),
          onSecondaryTap: () => showBulkActions(
            context,
            ref,
            records: selection.contains(record.id)
                ? <FeedRecord>[
                    for (final FeedRecord r in _records)
                      if (selection.contains(r.id)) r,
                  ]
                : <FeedRecord>[record],
          ),
          selecting: selection.isNotEmpty,
          isSelected:
              selection.contains(record.id) ||
              record.id == DetailHost.openOf(context),
          onTogglePaid: () => togglePaid(context, ref, record),
          onDelete: () => deleteRecord(context, ref, record),
          isFrozen: freeze.isFrozen(record.budgetPeriodId),
          isOverdue: record.isOverdue(today),
          isBeyondDeadline: beyondDeadline.contains(record.id),
          onLongPress: () =>
              ref.read(feedSelectionProvider.notifier).toggle(record.id),
          // The grip is outside the row's gesture area, so the row's long-press does not
          // compete with it.
          dragHandle: canReorder ? DragGrip(index: index) : null,
        );
    }
  }

  Future<void> _onReorder({
    required List<FeedItem> items,
    required int oldIndex,
    required int insertAt,
    required FeedOrderMode orderMode,
  }) async {
    final ReorderOutcome outcome = resolveReorder(
      items: items,
      oldIndex: oldIndex,
      insertAt: insertAt,
      orderMode: orderMode,
    );
    final Repositories repos = ref.read(repositoriesProvider);

    switch (outcome) {
      case ReorderRejected():
        return;

      case ReorderWithinDay(orderedIds: final List<String> ids):
        final Map<String, FeedRecord> byId = <String, FeedRecord>{
          for (final FeedItem item in items)
            if (item is FeedRow) item.record.id: item.record,
        };
        final Map<String, int> orders = <String, int>{
          for (int i = 0; i < ids.length; i++)
            ids[i]: i * PaymentRepository.sortOrderGap,
        };
        setState(() => _dropped = orders);

        // One transaction for the whole day.
        try {
          await repos.db.transaction(() async {
            for (final MapEntry<String, int> e in orders.entries) {
              final FeedRecord? record = byId[e.key];
              if (record == null || record.sortOrder == e.value) continue;
              if (record.isIncome) {
                await repos.incomes.setSortOrder(record.id, e.value);
              } else {
                await repos.payments.update(
                  record.id,
                  sortOrder: Value<int>(e.value),
                );
              }
            }
          });
        } catch (_) {
          if (mounted) setState(() => _dropped = null);
          rethrow;
        }

      case ReorderToOtherDay(
        recordId: final String id,
        suggestedDate: final CalendarDate suggested,
      ):
        final CalendarDate? date = await pickDate(context, suggested);
        if (date == null) return;
        final FeedRow? row = items
            .whereType<FeedRow>()
            .where((FeedRow r) => r.record.id == id)
            .firstOrNull;
        if (row == null) return;
        if (!mounted) return;
        await guardWrite(
          context,
          () => row.record.isIncome
              ? repos.incomes.update(
                  id,
                  expectedDate: Value<CalendarDate>(date),
                )
              : repos.payments.update(id, dueDate: Value<CalendarDate>(date)),
        );
        // The new date may belong to another period.
        ref.invalidate(periodRefreshProvider);
    }
  }
}

/// What the Feed draws, in any mode.
@immutable
class _FeedSource {
  const _FeedSource({
    required this.records,
    required this.today,
    required this.coverage,
    required this.moneyEndsAt,
    required this.available,
    required this.freeCash,
    required this.paid,
    required this.remaining,
    required this.byPeriod,
    required this.mode,
    this.beyondDeadline = const <String>{},
    this.hasIncome = true,
    this.leftAfter = const <String, Decimal>{},
  });

  final List<FeedRecord> records;
  final CalendarDate today;
  final Map<String, bool> coverage;

  /// Left to spend after each entry.
  final Map<String, Decimal> leftAfter;

  /// Row id to the side of the row where the cutoff falls.
  final Map<String, bool> moneyEndsAt;

  /// Null when the anchor income has no amount.
  final Decimal? available;

  /// Null when not covered or [available] is unknown.
  final Decimal? freeCash;

  String get availableLabel => switch (mode) {
    BudgetMode.incomeDriven => 'feed.income',
    BudgetMode.flow => 'feed.currentMoney',
    BudgetMode.budget => 'budget.fund',
  };

  /// The Dashboard's name for [freeCash].
  String get freeLabel =>
      mode == BudgetMode.budget ? 'budget.remaining' : 'dashboard.freeMoney';

  final Decimal paid;
  final Decimal remaining;

  final bool byPeriod;

  final BudgetMode mode;

  /// Dimmed and excluded.
  final Set<String> beyondDeadline;

  /// False for a cycle with no income; free money is then zero.
  final bool hasIncome;
}

/// The four figures above the list, in a 2x2 grid.
class _FeedTotals extends StatelessWidget implements PreferredSizeWidget {
  const _FeedTotals({
    required this.source,
    required this.money,
    required this.selector,
    required this.hasOverdue,
    this.onBalanceTap,
  });

  final _FeedSource source;
  final MoneyFormat money;

  /// Flow only: the balance opens its sheet, as on the Dashboard.
  final VoidCallback? onBalanceTap;

  final Widget? selector;

  /// The bar declares its height before the chip builds.
  final bool hasOverdue;

  static const double _tileHeight = 58;
  static const double _chipHeight = 56;

  @override
  Size get preferredSize => Size.fromHeight(
    (selector == null ? 8 : 48) +
        _tileHeight * 2 +
        20 +
        (hasOverdue ? _chipHeight : 0),
  );

  @override
  Widget build(BuildContext context) {
    final Decimal? available = source.available;
    final Decimal? free = source.hasIncome ? source.freeCash : Decimal.zero;

    // Only "not covered" is red.
    final String freeText = free != null
        ? money.format(free)
        : (available == null
              ? tr('income.amountUnknown')
              : tr('feed.runsShort'));

    // The bar declares its height up front, so its text grows only so far.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Readable(
        maxWidth: ShellLayout.of(context) == ShellMode.phone
            ? Readable.feed
            : Readable.feedTable,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            SageSpace.gutter,
            0,
            SageSpace.gutter,
            SageSpace.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ?selector,
              ..._tileRows(<Widget>[
                _Tile(
                  label: tr(source.availableLabel),
                  text: available == null
                      ? tr('income.amountUnknown')
                      : money.format(available),
                  value: available,
                  money: money,
                  highlighted: true,
                  onTap: onBalanceTap,
                ),
                _Tile(
                  label: tr(source.freeLabel),
                  text: freeText,
                  value: free,
                  money: money,
                  valueColor: free == null && available != null
                      ? context.sage.danger
                      : null,
                ),
                _Tile(
                  label: tr('dashboard.paid'),
                  text: money.format(source.paid),
                  value: source.paid,
                  money: money,
                ),
                _Tile(
                  label: tr('dashboard.leftToPay'),
                  text: money.format(source.remaining),
                  value: source.remaining,
                  money: money,
                ),
              ]),
              OverdueChip(
                money: money,
                margin: const EdgeInsets.only(top: SageSpace.sm),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on _FeedTotals {
  /// Two rows of two, or one row of four.
  List<Widget> _tileRows(List<Widget> tiles) {
    Widget row(List<Widget> part) => SizedBox(
      height: _FeedTotals._tileHeight,
      child: Row(
        children: <Widget>[
          for (int i = 0; i < part.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: SageSpace.sm),
            Expanded(child: part[i]),
          ],
        ],
      ),
    );
    return <Widget>[
      row(tiles.sublist(0, 2)),
      const SizedBox(height: SageSpace.sm),
      row(tiles.sublist(2)),
    ];
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.text,
    required this.value,
    required this.money,
    this.valueColor,
    this.highlighted = false,
    this.onTap,
  });

  final VoidCallback? onTap;

  final String label;

  /// Shown when [value] is null.
  final String text;

  final Decimal? value;

  final MoneyFormat money;
  final Color? valueColor;

  /// Accent tint.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme style = Theme.of(context).textTheme;

    return Material(
      color: highlighted ? sage.accentTint : sage.card,
      borderRadius: BorderRadius.circular(SageRadius.button),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SageRadius.button),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SageRadius.button),
            border: Border.all(color: sage.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style.bodySmall?.copyWith(color: sage.inkLabel),
              ),
              const SizedBox(height: 2),
              if (value != null)
                AnimatedMoney(value: value!, format: money.format)
              else
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style.titleSmall?.copyWith(color: valueColor),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.header,
    required this.today,
    required this.dates,
    this.band = false,
    this.empty = false,
    super.key,
  });

  final FeedHeader header;

  /// Nothing under it: a period's first day.
  final bool empty;
  final CalendarDate today;
  final DateLabels dates;

  /// A tinted row across the table, with the weekday.
  final bool band;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;

    final bool isToday = header.date == today;
    final String note = empty && !isToday ? ' · ${tr('feed.periodEmpty')}' : '';
    if (band) {
      final String day =
          dates.weekdayAndDate(header.date, reference: today) + note;
      return Container(
        height: _headerExtent * feedGrowth(context),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: SageSpace.gutter),
        decoration: BoxDecoration(
          color: sage.surface,
          border: Border(bottom: BorderSide(color: sage.hairline, width: 0.5)),
        ),
        child: Semantics(
          header: true,
          child: Text(
            isToday ? '${tr('feed.today')} · $day' : day,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.labelLarge?.copyWith(
              color: isToday ? sage.accentStrong : sage.inkSecondary,
            ),
          ),
        ),
      );
    }
    // Pinned to [_headerExtent] for the scroll arithmetic.
    return Container(
      height: _headerExtent * feedGrowth(context),
      alignment: Alignment.bottomLeft,
      padding: const EdgeInsets.fromLTRB(
        SageSpace.gutter,
        0,
        SageSpace.gutter,
        SageSpace.xs,
      ),
      child: Semantics(
        header: true,
        child: Text(
          isToday
              ? tr('feed.today')
              : dates.dayMonth(header.date, reference: today) + note,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.labelMedium?.copyWith(
            color: isToday ? sage.accentStrong : sage.inkLabel,
          ),
        ),
      ),
    );
  }
}

class _CutoffLine extends StatelessWidget {
  const _CutoffLine({required this.item, super.key});

  final FeedCutoff item;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return Container(
      height: _cutoffExtent * feedGrowth(context),
      padding: const EdgeInsets.symmetric(horizontal: SageSpace.gutter),
      // Equal lines either side, whatever the label's length.
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) => Row(
          children: <Widget>[
            Expanded(child: Container(height: 1, color: sage.danger)),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: box.maxWidth * 0.8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: SageSpace.sm),
                child: Text(
                  tr('feed.cutoff'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: sage.danger),
                ),
              ),
            ),
            Expanded(child: Container(height: 1, color: sage.danger)),
          ],
        ),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.count, required this.onClose});

  final int count;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
    color: context.sage.accentTint,
    padding: const EdgeInsets.only(left: SageSpace.gutter),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Text(
            tr(
              'feed.bulk.selected',
              namedArgs: <String, String>{'count': '$count'},
            ),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: tr('common.close'),
          onPressed: onClose,
        ),
      ],
    ),
  );
}

/// Explains the paid circle until closed.
class _TickHint extends StatelessWidget {
  const _TickHint({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        SageSpace.gutter,
        SageSpace.xs,
        SageSpace.gutter,
        SageSpace.xs,
      ),
      padding: const EdgeInsets.only(left: SageSpace.md),
      decoration: BoxDecoration(
        color: sage.accentTint,
        borderRadius: BorderRadius.circular(SageRadius.card),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.check_circle_outline, size: 20, color: sage.accentStrong),
          const SizedBox(width: SageSpace.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: SageSpace.md),
              child: Text(
                tr(desktopInput ? 'feed.tickHintDesktop' : 'feed.tickHint'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          IconButton(
            onPressed: onClose,
            tooltip: tr('common.close'),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

/// Above the table: the title, the period's figures, search and add.
class _TableToolbar extends StatelessWidget {
  const _TableToolbar({
    required this.source,
    required this.money,
    required this.filtered,
    required this.onAdd,
    required this.onSearch,
    required this.figures,
    this.onBalanceTap,
  });

  /// The period's figures, where the Dashboard is out of sight.
  final bool figures;

  final VoidCallback onSearch;

  final _FeedSource source;
  final MoneyFormat money;
  final bool filtered;

  final VoidCallback onAdd;

  /// Flow only: the balance opens its sheet.
  final VoidCallback? onBalanceTap;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    final Decimal? available = source.available;
    final Decimal? free = source.hasIncome ? source.freeCash : Decimal.zero;

    // A small tile: the mobile figures, shrunk.
    Widget figure(
      String label,
      String value, {
      Color? color,
      bool highlighted = false,
      VoidCallback? onTap,
    }) => Material(
      color: highlighted ? sage.accentTint : sage.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SageRadius.button),
        side: BorderSide(color: sage.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SageRadius.button),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SageSpace.md,
            vertical: 6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: text.labelSmall?.copyWith(color: sage.inkSecondary),
              ),
              Text(
                value,
                style: text.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color ?? sage.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // A tight column puts Add under the search.
    final Widget side = Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: SageSpace.sm,
        runSpacing: SageSpace.xs,
        children: <Widget>[
          Badge(
            isLabelVisible: filtered,
            backgroundColor: sage.accentStrong,
            smallSize: 8,
            child: OutlinedButton.icon(
              onPressed: onSearch,
              icon: const Icon(Icons.search, size: 18),
              label: Text(tr('feed.filter.title')),
            ),
          ),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: Text(tr('common.add')),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(SageSpace.md),
      // An invisible copy of the buttons on the left keeps the figures in the
      // middle, under the title.
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Flexible(
            flex: 2,
            child: ExcludeFocus(
              child: ExcludeSemantics(
                child: IgnorePointer(child: Opacity(opacity: 0, child: side)),
              ),
            ),
          ),
          const SizedBox(width: SageSpace.md),
          Expanded(
            flex: 3,
            child: !figures
                ? const SizedBox.shrink()
                : Wrap(
                    alignment: WrapAlignment.center,
                    spacing: SageSpace.sm,
                    runSpacing: SageSpace.xs,
                    children: <Widget>[
                      figure(
                        tr(source.availableLabel),
                        available == null
                            ? tr('income.amountUnknown')
                            : money.format(available),
                        highlighted: true,
                        onTap: onBalanceTap,
                      ),
                      figure(tr('dashboard.paid'), money.format(source.paid)),
                      figure(
                        tr('dashboard.leftToPay'),
                        money.format(source.remaining),
                      ),
                      figure(
                        tr(source.freeLabel),
                        free == null
                            ? tr('feed.runsShort')
                            : money.format(free),
                        color: free == null || free < Decimal.zero
                            ? sage.danger
                            : sage.accentStrong,
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: SageSpace.md),
          Flexible(flex: 2, child: side),
        ],
      ),
    );
  }
}

/// Grows and shrinks with its child; at once under reduced motion, where a
/// zero-length AnimatedSize re-lays itself out during layout and throws.
class _Unfold extends StatelessWidget {
  const _Unfold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MediaQuery.disableAnimationsOf(context)
      ? child
      : AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: child,
        );
}
