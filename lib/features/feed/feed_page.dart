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
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/core/ui/leaf_loader.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/dashboard/period_selector.dart';
import 'package:sielto/features/feed/feed_menu.dart';
import 'package:sielto/features/feed/feed_model.dart';
import 'package:sielto/features/feed/feed_reorder.dart';
import 'package:sielto/features/feed/feed_row.dart';
import 'package:sielto/features/feed/feed_window.dart';
import 'package:sielto/features/incomes/income_form_page.dart';
import 'package:sielto/features/incomes/receipt_dialog.dart';
import 'package:sielto/features/overdue/overdue.dart';
import 'package:sielto/features/payments/payment_form_page.dart';
import 'package:sielto/features/periods/freeze_providers.dart';
import 'package:sielto/features/periods/freeze_ui.dart';
import 'package:sielto/features/periods/period_service.dart';
import 'package:sielto/features/shell/app_header.dart';
import 'package:sielto/features/space/budget_ledger.dart';
import 'package:sielto/features/space/period_ledger.dart';
import 'package:sielto/features/space/space_ledger.dart';

/// The chronological list of payments and incomes (spec 4.5).
///
/// The Dashboard answers "how much"; this screen answers "what exactly, and
/// when". Both read the same walk, so the figures above the list are the same
/// numbers the Dashboard shows, not a second calculation.
class FeedPage extends ConsumerStatefulWidget {
  const FeedPage({super.key});

  @override
  ConsumerState<FeedPage> createState() => _FeedPageState();
}

/// Fixed extents, so the scroll offset can be mapped onto the list without
/// measuring every child.
const double _headerExtent = 40;
const double _cutoffExtent = 34;

class _FeedPageState extends ConsumerState<FeedPage> {
  final ScrollController _scroll = ScrollController();

  /// Anchors the quick-add bubble to the button that opens it.
  final GlobalKey _addButton = GlobalKey();

  /// The flattened list as last built, for the scroll listener and the arrows.
  List<FeedItem> _items = const <FeedItem>[];

  /// Where rows were just dropped, held until the query catches up.
  ///
  /// The reorder writes in one transaction, but the stream still emits a frame
  /// or two later, and every rebuild in between draws the order the rows had
  /// before the drag. Holding the new positions here means a dropped row stays
  /// where it was dropped instead of flicking back.
  Map<String, int>? _dropped;

  /// Set when the window widens, cleared once the wider list is built, so one
  /// arrival at an edge widens it once rather than on every scroll event.
  bool _extending = false;

  /// The top item before older months were added above it, so the view can
  /// stay on it instead of jumping three months back.
  FeedItem? _keptTop;

  /// Whether the list has been placed on the selected period yet. It opens
  /// there rather than three months back.
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

  /// Widens the visible window as the user reaches either end (spec 4.5), and
  /// keeps the period the figures describe in step with where the list is.
  void _extendOnEdge() {
    if (!_scroll.hasClients) return;
    _syncPeriodToScroll(_items);
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
        // Nothing recorded further yet: lay out more periods, whose incomes
        // then widen the window on the next pass.
        ref
            .read(periodReachProvider.notifier)
            .reach(window.to.addMonths(PeriodService.horizonStepMonths));
      }
    }
  }

  /// Whether any record falls where [test] says. Widening past the last
  /// record adds nothing, and the edge would ask again on the next frame.
  bool _anyRecord(bool Function(CalendarDate) test) =>
      (ref.read(spacePaymentsProvider).value ?? const <Payment>[]).any(
        (Payment p) => test(p.dueDate),
      ) ||
      (ref.read(spaceIncomesProvider).value ?? const <Income>[]).any(
        (Income i) => test(i.expectedDate),
      );

  /// Called once the list is built from a widened window.
  void _afterExtend(List<FeedItem> items) {
    _extending = false;
    final FeedItem? kept = _keptTop;
    _keptTop = null;
    if (kept == null) return;
    // Older rows landed above the view; move down by exactly their height.
    final double? y = _offsetOf(items, (FeedItem i) => _sameItem(i, kept));
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

  /// The scroll offset of the first item [test] accepts, or null.
  double? _offsetOf(List<FeedItem> items, bool Function(FeedItem) test) {
    final double rowHeight = rowHeightFor(ref.read(feedDensityProvider));
    double y = 0;
    for (final FeedItem item in items) {
      if (test(item)) return y;
      y += _extentOf(item, rowHeight);
    }
    return null;
  }

  static double _extentOf(FeedItem item, double rowHeight) => switch (item) {
    FeedHeader() => _headerExtent,
    FeedCutoff() => _cutoffExtent,
    FeedRow() => rowHeight,
  };

  /// Room under the last row, enough for the last period to reach the top.
  ///
  /// The selected period follows the top visible day, so without it the list
  /// ended with an earlier period still on top: the last cycles could never
  /// be selected by scrolling, and the arrows bounced back from them.
  double _bottomSlack(List<FeedItem> items, double viewport, bool byPeriod) {
    const double floor = 96;
    final BudgetPeriod? last = ref.read(incomePeriodsProvider).lastOrNull;
    if (!byPeriod || last == null) return floor;
    final double? start = _offsetOf(
      items,
      (FeedItem i) => i is FeedHeader && !i.date.isBefore(last.startDate),
    );
    if (start == null) return floor;
    final double rowHeight = rowHeightFor(ref.read(feedDensityProvider));
    double total = 0;
    for (final FeedItem item in items) {
      total += _extentOf(item, rowHeight);
    }
    return math.max(floor, viewport - (total - start));
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

    final _FeedSource? source = _source(space);
    if (source == null) {
      return Scaffold(
        backgroundColor: context.sage.surface,
        appBar: AppHeader(title: tr('nav.feed')),
        body: const Center(child: LeafLoader()),
      );
    }

    _items = buildFeedItems(
      records: source.records,
      orderMode: space.feedOrderMode,
      coverage: source.coverage,
      moneyEndsAt: source.moneyEndsAt,
    );
    final List<FeedItem> items = _items;
    if (_extending) _afterExtend(items);
    // A list that fits the screen never scrolls, so no scroll event would
    // ever reach an edge. Check once the frame is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _extendOnEdge();
    });
    if (!_placed && items.isNotEmpty) {
      _placed = true;
      final BudgetPeriod? selected = ref.read(selectedPeriodProvider);
      if (source.byPeriod && selected != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollToPeriod(selected, items, animate: false),
        );
      }
    }
    final bool atBottom = ref
        .watch(controlsAtBottomProvider)
        .contains(ControlsScreen.feed);
    final Widget selector = PeriodSelector(
      onJump: (BudgetPeriod p) => _scrollToPeriod(p, items),
      swipe: !atBottom,
    );

    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: AppHeader(
        title: tr('nav.feed'),
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
          Expanded(
            child: items.isEmpty
                // No button of its own: the add menu is on the button that is
                // always there, and a second one that adds only a payment
                // teaches the wrong shortcut on the emptiest screen.
                ? EmptyState(message: tr('feed.empty'))
                : LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints box) =>
                        ReorderableListView.builder(
                          scrollController: _scroll,
                          buildDefaultDragHandles: false,
                          padding: EdgeInsets.only(
                            bottom: _bottomSlack(
                              items,
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
                                locale: locale,
                                today: source.today,
                                categories:
                                    categories.value ??
                                    const <String, Category>{},
                                freeze: ref.watch(freezeLookupProvider),
                                beyondDeadline: source.beyondDeadline,
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

  /// What the list draws, and the four figures above it.
  ///
  /// One continuous list in every mode: the Feed scrolls into the past and the
  /// future and is deliberately not clipped to a period (spec 4.5).
  ///
  /// Every cycle contributes its own coverage and its own cutoff line, so the
  /// list is the same whichever period is selected. Only the figures follow the
  /// scroll — which is what keeps crossing a boundary from redrawing the rows
  /// under the finger.
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

      // Before the first regular income there are no cycles at all, which is a
      // valid permanent state: the list still shows, with no cycle figures over
      // it (spec 4.7). Zero, not unknown — nothing is coming, and that is what
      // zero means.
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
        // With no fund there is nothing to fit into, so the figures say what
        // the fund holds — zero — rather than pretending to a limit.
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

  /// Overlays the order a drag just produced, and drops the overlay once the
  /// records read back the same way.
  ///
  /// Clearing here rather than after the write is deliberate: the write
  /// finishing says nothing about the stream having emitted, and the overlay is
  /// only stale once the rows themselves agree with it.
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

  /// Follows the list: the period the top visible day belongs to becomes the
  /// selected one, so the figures above and the Dashboard both track the
  /// scroll instead of a separate control.
  void _syncPeriodToScroll(List<FeedItem> items) {
    final List<BudgetPeriod> periods = ref.read(incomePeriodsProvider);
    if (periods.isEmpty || !_scroll.hasClients) return;

    final CalendarDate? top = _topVisibleDate(items);
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

  /// The date of the first row at or below the top of the viewport.
  ///
  /// Rows are a fixed extent per density and headers a fixed height, so the
  /// offset maps onto the flattened list arithmetically rather than by asking
  /// every child where it is.
  CalendarDate? _topVisibleDate(List<FeedItem> items) {
    final double offset = _scroll.position.pixels;
    final double rowHeight = rowHeightFor(ref.read(feedDensityProvider));

    double y = 0;
    CalendarDate? lastHeader;
    for (final FeedItem item in items) {
      final double h = switch (item) {
        FeedHeader() => _headerExtent,
        FeedCutoff() => _cutoffExtent,
        FeedRow() => rowHeight,
      };
      if (item is FeedHeader) lastHeader = item.date;
      if (y + h > offset) return lastHeader ?? _firstDateOf(items);
      y += h;
    }
    return lastHeader;
  }

  CalendarDate? _firstDateOf(List<FeedItem> items) {
    for (final FeedItem item in items) {
      if (item is FeedHeader) return item.date;
    }
    return null;
  }

  /// Scrolls the list to where a period begins.
  ///
  /// The arrows move the list rather than filtering it: the Feed stays one
  /// continuous run of records, and the buttons are a way to travel it.
  void _scrollToPeriod(
    BudgetPeriod period,
    List<FeedItem> items, {
    bool animate = true,
  }) {
    if (!_scroll.hasClients) return;
    final double? y = _offsetOf(
      items,
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
    required String locale,
    required CalendarDate today,
    required Map<String, Category> categories,
    required FreezeLookup freeze,
    required Set<String> beyondDeadline,
  }) {
    switch (item) {
      case FeedHeader():
        return _DayHeader(
          key: ValueKey<String>(item.key),
          header: item,
          today: today,
          dates: DateLabels(locale),
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
          onTap: () => _edit(record),
          onTogglePaid: () => _togglePaid(record),
          onDelete: () => _delete(record),
          isFrozen: freeze.isFrozen(record.budgetPeriodId),
          isOverdue: record.isOverdue(today),
          isBeyondDeadline: beyondDeadline.contains(record.id),
          onLongPress: () =>
              showRecordMenu(context, ref, record: record, today: today),
          // The grip is its own gesture area beside the row, not on top of it,
          // so a press here picks the row up on contact and holds it for as
          // long as the finger stays down. Wrapped in a swallowing detector it
          // competed with the row's long-press and the add menu won.
          dragHandle: ReorderableDragStartListener(
            index: index,
            child: Padding(
              // A finger-sized target around a small glyph.
              padding: const EdgeInsets.fromLTRB(
                SageSpace.sm,
                SageSpace.md,
                SageSpace.md,
                SageSpace.md,
              ),
              child: Icon(
                Icons.drag_indicator,
                size: 20,
                color: context.sage.inkLabel,
              ),
            ),
          ),
        );
    }
  }

  void _edit(FeedRecord record) {
    if (record.isIncome) {
      openIncomeForm(context, incomeId: record.id, date: record.date);
      return;
    }
    openPaymentForm(context, paymentId: record.id, date: record.date);
  }

  /// Marking something paid never asks; clearing the mark on a mandatory
  /// payment does (spec 4.5).
  Future<void> _togglePaid(FeedRecord record) async {
    final Repositories repos = ref.read(repositoriesProvider);
    final bool next = !record.isPaid;

    if (!next && record.isMandatory && !await confirmMandatory(context)) {
      return;
    }
    if (!mounted) return;

    if (record.isIncome) {
      if (next && record.amount == null) {
        // An amount is required before a receipt can be confirmed, or the
        // period's figures would stay uncomputable (spec 4.5).
        if (mounted) {
          openIncomeForm(context, incomeId: record.id, date: record.date);
        }
        return;
      }

      // Confirming a receipt is not a bare flag: the spec asks for the date
      // the money actually arrived, defaulting to the expected one (spec 5.4).
      CalendarDate? actual;
      if (next) {
        if (!mounted) return;
        actual = await askReceiptDate(context, expected: record.date);
        if (actual == null) return;
      }
      if (!mounted) return;

      await guardFreeze(
        context,
        () => repos.incomes.update(
          record.id,
          isPaid: Value<bool>(next),
          // Clearing the receipt clears the fact with it (spec 5.4).
          actualDate: Value<CalendarDate?>(actual),
        ),
      );
      // An anchor arriving early moves the cycle it opens (spec 5.4).
      ref.invalidate(periodRefreshProvider);
      return;
    }
    await guardFreeze(
      context,
      () => repos.payments.setPaid(record.id, isPaid: next),
    );
  }

  Future<void> _delete(FeedRecord record) async {
    if (record.isMandatory && !await confirmMandatory(context)) return;
    if (!mounted) return;
    final Repositories repos = ref.read(repositoriesProvider);

    final bool deleted = await guardFreeze(
      context,
      () => record.isIncome
          ? repos.incomes.softDelete(record.id)
          : repos.payments.softDelete(record.id),
    );
    ref.invalidate(periodRefreshProvider);
    if (!deleted || !mounted) return;
    showUndoSnackbar(
      context,
      message: tr(
        'feed.deleted',
        namedArgs: <String, String>{'title': record.title},
      ),
      onUndo: () async {
        if (record.isIncome) {
          await repos.incomes.restore(record.id);
        } else {
          await repos.payments.restore(record.id);
        }
      },
    );
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
        // Snapback: the list rebuilds from the unchanged query.
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
        // Drawn from here until the query agrees, so the drop is final on
        // screen the moment the finger lifts.
        setState(() => _dropped = orders);

        // One transaction for the whole day. Written row by row, the query
        // behind the list re-emits after each one and the Feed draws every
        // half-finished order on the way.
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
          // Nothing was stored, so the overlay would hold an order that never
          // becomes true.
          if (mounted) setState(() => _dropped = null);
          rethrow;
        }

      case ReorderToOtherDay(
        recordId: final String id,
        suggestedDate: final CalendarDate suggested,
      ):
        // The picker opens prefilled and writes nothing until confirmed
        // (spec 4.5).
        final DateTime? picked = await showDatePicker(
          context: context,
          initialDate: suggested.toUtcMidnight(),
          firstDate: DateTime.utc(suggested.year - 5),
          lastDate: DateTime.utc(suggested.year + 10),
        );
        if (picked == null) return;
        final CalendarDate date = CalendarDate.fromDateTime(picked);
        final FeedRow? row = items
            .whereType<FeedRow>()
            .where((FeedRow r) => r.record.id == id)
            .firstOrNull;
        if (row == null) return;
        if (!mounted) return;
        await guardFreeze(
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

/// What the Feed draws, whichever mode produced it.
///
/// The two modes disagree about which records belong on screen and about what
/// the starting sum is, and about nothing else; collapsing that disagreement
/// here keeps one list, one reorder path and one row widget.
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

  /// Row id to which side of it the cutoff line falls, one entry per cycle.
  final Map<String, bool> moneyEndsAt;

  /// The sum the walk started from. Null when it is not known — an anchor
  /// income with no amount yet (spec 4.7).
  final Decimal? available;

  /// Null when the plan is not covered, or when [available] is unknown.
  final Decimal? freeCash;

  /// What the starting sum is called in this mode. The figure is the same
  /// shape everywhere; what it means is not.
  String get availableLabel => switch (mode) {
    BudgetMode.incomeDriven => 'feed.income',
    BudgetMode.flow => 'feed.currentMoney',
    BudgetMode.budget => 'budget.fund',
  };

  /// Of the plan, what is settled and what is still owed (spec 4.5).
  final Decimal paid;
  final Decimal remaining;

  final bool byPeriod;

  final BudgetMode mode;

  /// Records a hard deadline moved past. Drawn dimmed and left out of the
  /// reckoning, never deleted (spec 4.8).
  final Set<String> beyondDeadline;

  /// False for a cycle with no income: a remainder there would only be the
  /// payments negated, so the free figure is zero.
  final bool hasIncome;
}

/// Income and Free money for the current context, above the list (spec 4.5).
/// The four figures of the current context, over the list (design section 4.5).
///
/// A 2x2 grid rather than a row of columns: four numbers side by side wrap at
/// any real type size, and the pairing says something — what came in against
/// what is free, what is settled against what is not.
class _FeedTotals extends StatelessWidget implements PreferredSizeWidget {
  const _FeedTotals({
    required this.source,
    required this.money,
    required this.selector,
    required this.hasOverdue,
  });

  final _FeedSource source;
  final MoneyFormat money;

  /// The period arrows, when there is a period to move between.
  final Widget? selector;

  /// Whether the missed-payments chip takes a row of its own. The bar has to
  /// declare its height before the chip can decide it is empty.
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
    // No income is zero, not the payments negated.
    final Decimal? free = source.hasIncome ? source.freeCash : Decimal.zero;

    // Not covered and not computable are different answers, and only one of
    // them is red.
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
          // What is already late, under the figures that describe what is
          // still ahead. Draws nothing when there is nothing missed.
          OverdueChip(
            money: money,
            margin: const EdgeInsets.only(top: SageSpace.sm),
          ),
        ],
      ),
    );
  }
}

/// One figure on its own card: label above, amount below, both centred.
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

  /// What to draw when there is no figure to wind to.
  final String text;

  /// Null where the answer is a word rather than a number.
  final Decimal? value;

  final MoneyFormat money;
  final Color? valueColor;

  /// The income tile carries the accent tint, as the one figure the others are
  /// measured against.
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
          // The tween is the point when the period changes: the figures wind
          // rather than swap, so a move between cycles reads as a move
          // (spec 4.5, 10.5).
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

/// The day a group of records falls on (spec 4.5).
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
    // Exactly the extent the scroll arithmetic counts. Left to its padding the
    // header came out 33px against 40, and the gap grew by a day's worth each
    // header until the selected period lagged the list by weeks.
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

/// The line where the money runs out (spec 4.9).
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
