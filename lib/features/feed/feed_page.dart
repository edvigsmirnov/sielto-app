import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/payment_repository.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/settings/local_settings.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/form_fields.dart';
import 'package:sielto/core/ui/leaf_loader.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/dashboard/period_selector.dart';
import 'package:sielto/features/feed/feed_filter.dart';
import 'package:sielto/features/feed/feed_menu.dart';
import 'package:sielto/features/feed/feed_model.dart';
import 'package:sielto/features/feed/feed_reorder.dart';
import 'package:sielto/features/feed/feed_row.dart';
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

  final GlobalKey _addButton = GlobalKey();

  /// Last built list, for the scroll listener and the arrows.
  List<FeedItem> _items = const <FeedItem>[];

  /// Offset of each item in [_items], plus the total at the end.
  List<double> _starts = const <double>[0];

  /// Date of the last header at or before each item in [_items].
  List<CalendarDate?> _headers = const <CalendarDate?>[];

  bool _edgeCheckQueued = false;

  /// Order just dropped, shown until the query reads it back.
  Map<String, int>? _dropped;

  /// True from widening the window until the wider list is built.
  bool _extending = false;

  /// Top item before older rows were added above, to keep the view in place.
  FeedItem? _keptTop;

  /// Whether the list has been scrolled to the selected period.
  bool _placed = false;

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

  /// Widens the window at either end and syncs the selected period.
  void _extendOnEdge() {
    if (!_scroll.hasClients) return;
    _syncPeriodToScroll();
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

  void _measure(List<FeedItem> items, double rowHeight) {
    final List<double> starts = <double>[0];
    final List<CalendarDate?> headers = <CalendarDate?>[];
    CalendarDate? header;
    for (final FeedItem item in items) {
      if (item is FeedHeader) header = item.date;
      headers.add(header);
      starts.add(starts.last + _extentOf(item, rowHeight));
    }
    _starts = starts;
    _headers = headers;
  }

  static double _extentOf(FeedItem item, double rowHeight) => switch (item) {
    FeedHeader() => _headerExtent,
    FeedCutoff() => _cutoffExtent,
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
    final FeedDensity density = ref.watch(feedDensityProvider);
    final String locale = context.locale.toString();
    final MoneyFormat money = MoneyFormat(
      locale: locale,
      currencyCode: space.currencyCode,
    );
    final DateLabels dates = DateLabels(locale);

    final _FeedSource? source = _source(space);
    if (source == null) {
      return Scaffold(
        backgroundColor: context.sage.surface,
        appBar: AppHeader(title: tr('nav.feed')),
        body: const Center(child: LeafLoader()),
      );
    }

    final FeedFilter filter = ref.watch(feedFilterProvider);
    _items = buildFeedItems(
      records: filter.isActive
          ? source.records.where(filter.matches).toList()
          : source.records,
      orderMode: space.feedOrderMode,
      coverage: source.coverage,
      moneyEndsAt: source.moneyEndsAt,
    );
    final List<FeedItem> items = _items;
    _measure(items, rowHeightFor(density));
    if (_extending) _afterExtend(items);
    // Checks the edges after layout: a list that fits never scrolls.
    if (!_edgeCheckQueued) {
      _edgeCheckQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _edgeCheckQueued = false;
        if (mounted) _extendOnEdge();
      });
    }
    if (!_placed && items.isNotEmpty) {
      _placed = true;
      final BudgetPeriod? selected = ref.read(selectedPeriodProvider);
      if (source.byPeriod && selected != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollToPeriod(selected, animate: false),
        );
      }
    }
    final bool atBottom = ref
        .watch(controlsAtBottomProvider)
        .contains(ControlsScreen.feed);
    final Widget selector = PeriodSelector(
      onJump: (BudgetPeriod p) => _scrollToPeriod(p),
      swipe: !atBottom,
    );

    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: AppHeader(
        title: tr('nav.feed'),
        trailing: <Widget>[
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
        bottom: _FeedTotals(
          source: source,
          money: money,
          hasOverdue: !ref.watch(overduePaymentsProvider).isEmpty,
          selector: source.byPeriod && !atBottom ? selector : null,
        ),
      ),
      bottomNavigationBar: source.byPeriod && atBottom
          ? SafeArea(top: false, child: selector)
          : null,
      floatingActionButton: FloatingActionButton(
        key: _addButton,
        backgroundColor: context.sage.accent,
        foregroundColor: context.sage.accentOn,
        shape: const CircleBorder(),
        onPressed: () => showQuickAddMenu(
          context,
          ref,
          today: source.today,
          anchorKey: _addButton,
        ),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: <Widget>[
          if (filter.isActive)
            FeedFilterBar(shown: _allMatches(filter), money: money),
          Expanded(
            child: items.isEmpty
                ? EmptyState(
                    message: tr(
                      filter.isActive ? 'feed.filter.nothing' : 'feed.empty',
                    ),
                  )
                : LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints box) =>
                        ReorderableListView.builder(
                          scrollController: _scroll,
                          buildDefaultDragHandles: false,
                          padding: EdgeInsets.only(
                            bottom: _bottomSlack(
                              box.maxHeight,
                              source.byPeriod,
                            ),
                          ),
                          itemCount: items.length,
                          itemBuilder: (BuildContext context, int index) =>
                              _buildItem(
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
                                canReorder: !filter.isActive,
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
        ],
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
      for (final PeriodLedger ledger in ledgers) {
        coverage.addAll(ledger.coverageByEntry);
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

    if (space.budgetMode == BudgetMode.budget) {
      final BudgetLedger? budget = ref.watch(budgetLedgerProvider).value;
      if (budget == null) return null;
      return _FeedSource(
        records: records,
        today: budget.today,
        coverage: budget.coverageByEntry,
        moneyEndsAt: budget.moneyEndsAt,
        available: budget.available,
        freeCash: budget.hasFund ? budget.remaining : budget.available,
        paid: budget.totalPaid,
        remaining: budget.totalRemaining,
        byPeriod: false,
        mode: space.budgetMode,
        beyondDeadline: budget.beyondDeadline,
      );
    }

    final FlowLedger? flow = ref.watch(flowLedgerProvider).value;
    if (flow == null) return null;
    final ({String entryId, bool below})? end = flow.cascade.moneyEndsAt;
    return _FeedSource(
      records: records,
      today: flow.today,
      coverage: flow.coverageByEntry,
      moneyEndsAt: <String, bool>{if (end != null) end.entryId: end.below},
      available: flow.available,
      freeCash: flow.freeCash,
      paid: flow.totalPaid,
      remaining: flow.totalRemaining,
      byPeriod: false,
      mode: space.budgetMode,
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
    final double? y = _offsetOf(
      (FeedItem i) => i is FeedHeader && !i.date.isBefore(period.startDate),
    );
    if (y == null) return;
    final double target = y.clamp(
      _scroll.position.minScrollExtent,
      _scroll.position.maxScrollExtent,
    );
    if (!animate) {
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
  }) {
    switch (item) {
      case FeedHeader():
        return _DayHeader(
          key: ValueKey<String>(item.key),
          header: item,
          today: today,
          dates: dates,
        );
      case FeedCutoff():
        return _CutoffLine(key: ValueKey<String>(item.key), item: item);
      case FeedRow():
        final FeedRecord record = item.record;
        return FeedRowTile(
          key: ValueKey<String>(item.key),
          record: record,
          isCovered: item.isCovered,
          density: density,
          money: money,
          category: record.categoryId == null
              ? null
              : categories[record.categoryId],
          onTap: () => editRecord(context, record),
          onTogglePaid: () => togglePaid(context, ref, record),
          onDelete: () => deleteRecord(context, ref, record),
          isFrozen: freeze.isFrozen(record.budgetPeriodId),
          isOverdue: record.isOverdue(today),
          isBeyondDeadline: beyondDeadline.contains(record.id),
          onLongPress: () =>
              showRecordMenu(context, ref, record: record, today: today),
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
  });

  final List<FeedRecord> records;
  final CalendarDate today;
  final Map<String, bool> coverage;

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
  });

  final _FeedSource source;
  final MoneyFormat money;

  final Widget? selector;

  /// The bar declares its height before the chip builds.
  final bool hasOverdue;

  static const double _tileHeight = 58;
  static const double _chipHeight = 48;

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
              : tr('dashboard.notCovered'));

    return Padding(
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
          SizedBox(
            height: _tileHeight,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _Tile(
                    label: tr(source.availableLabel),
                    text: available == null
                        ? tr('income.amountUnknown')
                        : money.format(available),
                    value: available,
                    money: money,
                    highlighted: true,
                  ),
                ),
                const SizedBox(width: SageSpace.sm),
                Expanded(
                  child: _Tile(
                    label: tr('dashboard.freeMoney'),
                    text: freeText,
                    value: free,
                    money: money,
                    valueColor: free == null && available != null
                        ? context.sage.danger
                        : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SageSpace.sm),
          SizedBox(
            height: _tileHeight,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _Tile(
                    label: tr('dashboard.paid'),
                    text: money.format(source.paid),
                    value: source.paid,
                    money: money,
                  ),
                ),
                const SizedBox(width: SageSpace.sm),
                Expanded(
                  child: _Tile(
                    label: tr('dashboard.leftToPay'),
                    text: money.format(source.remaining),
                    value: source.remaining,
                    money: money,
                  ),
                ),
              ],
            ),
          ),
          OverdueChip(
            money: money,
            margin: const EdgeInsets.only(top: SageSpace.sm),
          ),
        ],
      ),
    );
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
  });

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

    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: highlighted ? sage.accentTint : sage.card,
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
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.header,
    required this.today,
    required this.dates,
    super.key,
  });

  final FeedHeader header;
  final CalendarDate today;
  final DateLabels dates;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;

    final bool isToday = header.date == today;
    // Pinned to [_headerExtent] for the scroll arithmetic.
    return Container(
      height: _headerExtent,
      alignment: Alignment.bottomLeft,
      padding: const EdgeInsets.fromLTRB(
        SageSpace.gutter,
        0,
        SageSpace.gutter,
        SageSpace.xs,
      ),
      child: Text(
        isToday
            ? tr('feed.today')
            : dates.dayMonth(header.date, reference: today),
        style: text.labelMedium?.copyWith(
          color: isToday ? sage.accentStrong : sage.inkLabel,
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
      height: _cutoffExtent,
      padding: const EdgeInsets.symmetric(horizontal: SageSpace.gutter),
      child: Row(
        children: <Widget>[
          Expanded(child: Container(height: 1, color: sage.danger)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SageSpace.sm),
            child: Text(
              tr('feed.cutoff'),
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: sage.danger),
            ),
          ),
          Expanded(child: Container(height: 1, color: sage.danger)),
        ],
      ),
    );
  }
}
