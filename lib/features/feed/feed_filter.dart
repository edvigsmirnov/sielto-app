import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/categories/category_colors.dart';
import 'package:sielto/features/categories/category_title.dart';
import 'package:sielto/features/feed/feed_model.dart';
import 'package:sielto/features/space/space_ledger.dart';

enum FeedKind { all, mandatory, variable, income }

enum FeedStatus { all, done, pending }

/// Named the way the type reads it: paid for expenses, received for incomes.
String statusLabel(FeedStatus status, FeedKind kind) => switch (status) {
  FeedStatus.all => tr('feed.filter.status.all'),
  _ => tr(
    'feed.filter.status.${switch (kind) {
      FeedKind.all => 'any',
      FeedKind.income => 'income',
      FeedKind.mandatory || FeedKind.variable => 'expense',
    }}.${status.name}',
  ),
};

/// Every condition must hold. Empty [categoryIds] means any category.
@immutable
class FeedFilter {
  const FeedFilter({
    this.query = '',
    this.kind = FeedKind.all,
    this.status = FeedStatus.all,
    this.categoryIds = const <String>{},
  });

  static const FeedFilter none = FeedFilter();

  /// Matched against the title and the notes, ignoring case.
  final String query;
  final FeedKind kind;
  final FeedStatus status;
  final Set<String> categoryIds;

  bool get isActive =>
      query.trim().isNotEmpty ||
      kind != FeedKind.all ||
      status != FeedStatus.all ||
      categoryIds.isNotEmpty;

  bool matches(FeedRecord r) {
    final bool kindFits = switch (kind) {
      FeedKind.all => true,
      FeedKind.income => r.isIncome,
      FeedKind.mandatory => r.expenseType == ExpenseType.mandatory,
      FeedKind.variable => r.expenseType == ExpenseType.variable,
    };
    if (!kindFits) return false;
    if (status == FeedStatus.done && !r.isPaid) return false;
    if (status == FeedStatus.pending && r.isPaid) return false;
    if (categoryIds.isNotEmpty && !categoryIds.contains(r.categoryId)) {
      return false;
    }
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return r.title.toLowerCase().contains(q) ||
        (r.notes?.toLowerCase().contains(q) ?? false);
  }

  /// [id] added to the categories, or removed when there.
  FeedFilter toggled(String id) => copyWith(
    categoryIds: categoryIds.contains(id)
        ? (Set<String>.of(categoryIds)..remove(id))
        : <String>{...categoryIds, id},
  );

  FeedFilter copyWith({
    String? query,
    FeedKind? kind,
    FeedStatus? status,
    Set<String>? categoryIds,
  }) => FeedFilter(
    query: query ?? this.query,
    kind: kind ?? this.kind,
    status: status ?? this.status,
    categoryIds: categoryIds ?? this.categoryIds,
  );
}

/// Kept for the session, cleared when the Space changes.
class FeedFilterController extends Notifier<FeedFilter> {
  @override
  FeedFilter build() {
    ref.watch(currentSpaceIdProvider);
    return FeedFilter.none;
  }

  void set(FeedFilter filter) => state = filter;

  void update(FeedFilter Function(FeedFilter) change) => state = change(state);

  void clear() => state = FeedFilter.none;
}

final NotifierProvider<FeedFilterController, FeedFilter> feedFilterProvider =
    NotifierProvider<FeedFilterController, FeedFilter>(
      FeedFilterController.new,
    );

Future<void> showFeedFilter(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (BuildContext _) => const _FilterSheet(),
);

/// Whether the wide layouts' search panel is open above the Feed.
class FeedFilterOpenController extends Notifier<bool> {
  @override
  bool build() => false;

  void set({required bool open}) => state = open;
}

final NotifierProvider<FeedFilterOpenController, bool> feedFilterOpenProvider =
    NotifierProvider<FeedFilterOpenController, bool>(
      FeedFilterOpenController.new,
    );

/// The wide layouts' search: a field, chip rows and what matched, above the
/// table. Escape closes it.
class FeedFilterPanel extends ConsumerStatefulWidget {
  const FeedFilterPanel({required this.shown, required this.money, super.key});

  final List<FeedRecord> shown;
  final MoneyFormat money;

  @override
  ConsumerState<FeedFilterPanel> createState() => _FeedFilterPanelState();
}

class _FeedFilterPanelState extends ConsumerState<FeedFilterPanel> {
  late final TextEditingController _query = TextEditingController(
    text: ref.read(feedFilterProvider).query,
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _update(FeedFilter Function(FeedFilter) change) =>
      ref.read(feedFilterProvider.notifier).update(change);

  void _close() => ref.read(feedFilterOpenProvider.notifier).set(open: false);

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    final FeedFilter filter = ref.watch(feedFilterProvider);
    final List<Category> categories =
        ref.watch(spaceCategoriesProvider).value ?? const <Category>[];

    Widget row(String label, List<Widget> chips) => Padding(
      padding: const EdgeInsets.only(top: SageSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(
                label,
                style: text.labelMedium?.copyWith(color: sage.inkSecondary),
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: SageSpace.xs,
              runSpacing: SageSpace.xs,
              children: chips,
            ),
          ),
        ],
      ),
    );

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(
          SageSpace.md,
          0,
          SageSpace.md,
          SageSpace.md,
        ),
        padding: const EdgeInsets.fromLTRB(
          SageSpace.gutter,
          SageSpace.md,
          SageSpace.md,
          SageSpace.sm,
        ),
        decoration: BoxDecoration(
          color: sage.card,
          borderRadius: BorderRadius.circular(SageRadius.card),
          border: Border.all(color: sage.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _query,
                    focusNode: _focus,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, size: 20),
                      hintText: tr('feed.filter.search'),
                      isDense: true,
                    ),
                    onChanged: (String value) =>
                        _update((FeedFilter f) => f.copyWith(query: value)),
                  ),
                ),
                const SizedBox(width: SageSpace.sm),
                OutlinedButton(
                  onPressed: filter.isActive
                      ? () {
                          _query.clear();
                          ref.read(feedFilterProvider.notifier).clear();
                        }
                      : null,
                  child: Text(tr('common.clear')),
                ),
                IconButton(
                  tooltip: tr('common.close'),
                  onPressed: _close,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            row(tr('feed.table.kind'), <Widget>[
              for (final FeedKind k in FeedKind.values)
                _Chip(
                  label: tr('feed.filter.kind.${k.name}'),
                  selected: filter.kind == k,
                  onTap: () => _update((FeedFilter f) => f.copyWith(kind: k)),
                ),
            ]),
            if (categories.isNotEmpty)
              row(tr('feed.table.category'), <Widget>[
                for (final Category c in categories)
                  _Chip(
                    label: c.shownTitle,
                    dot: parseCategoryColor(c.color),
                    selected: filter.categoryIds.contains(c.id),
                    onTap: () => _update((FeedFilter f) => f.toggled(c.id)),
                  ),
              ]),
            row(tr('feed.filter.statusLabel'), <Widget>[
              for (final FeedStatus st in FeedStatus.values)
                _Chip(
                  label: statusLabel(st, filter.kind),
                  selected: filter.status == st,
                  onTap: () =>
                      _update((FeedFilter f) => f.copyWith(status: st)),
                ),
            ]),
            const SizedBox(height: SageSpace.sm),
            const Hairline(),
            Padding(
              padding: const EdgeInsets.only(top: SageSpace.sm),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _found(widget.shown, widget.money),
                      style: text.bodySmall?.copyWith(color: sage.ink),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      tr('feed.filter.keys'),
                      textAlign: TextAlign.end,
                      style: text.bodySmall?.copyWith(color: sage.inkLabel),
                    ),
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

/// A small pill that toggles one condition.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.dot,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? sage.accent : sage.card,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? sage.accent : sage.border),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (dot case final Color color) ...<Widget>[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: selected ? sage.accentOn : sage.ink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet();

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late final TextEditingController _query = TextEditingController(
    text: ref.read(feedFilterProvider).query,
  );

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _update(FeedFilter Function(FeedFilter) change) =>
      ref.read(feedFilterProvider.notifier).update(change);

  @override
  Widget build(BuildContext context) {
    final FeedFilter filter = ref.watch(feedFilterProvider);
    final List<Category> categories =
        ref.watch(spaceCategoriesProvider).value ?? const <Category>[];
    final TextTheme text = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          SageSpace.gutter,
          0,
          SageSpace.gutter,
          SageSpace.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: _query,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 20),
                  hintText: tr('feed.filter.search'),
                  isDense: true,
                ),
                onChanged: (String value) =>
                    _update((FeedFilter f) => f.copyWith(query: value)),
              ),
              const SizedBox(height: SageSpace.lg),
              SegmentedChoice<FeedKind>(
                values: FeedKind.values,
                selected: filter.kind,
                labelOf: (FeedKind k) => tr('feed.filter.kind.${k.name}'),
                onChanged: (FeedKind k) =>
                    _update((FeedFilter f) => f.copyWith(kind: k)),
              ),
              const SizedBox(height: SageSpace.sm),
              SegmentedChoice<FeedStatus>(
                values: FeedStatus.values,
                selected: filter.status,
                labelOf: (FeedStatus s) => statusLabel(s, filter.kind),
                onChanged: (FeedStatus s) =>
                    _update((FeedFilter f) => f.copyWith(status: s)),
              ),
              if (categories.isNotEmpty) ...<Widget>[
                const SizedBox(height: SageSpace.lg),
                Text(tr('category.title'), style: text.labelLarge),
                const SizedBox(height: SageSpace.sm),
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints box) {
                    final int perRow = box.maxWidth >= 640 ? 4 : 2;
                    return Wrap(
                      spacing: SageSpace.sm,
                      runSpacing: SageSpace.sm,
                      children: <Widget>[
                        for (final Category c in categories)
                          SizedBox(
                            width:
                                (box.maxWidth - SageSpace.sm * (perRow - 1)) /
                                perRow,
                            child: FilterChip(
                              avatar: CategoryMark(
                                color: c.color,
                                icon: c.icon,
                                size: 22,
                              ),
                              label: SizedBox(
                                width: double.infinity,
                                child: Text(
                                  c.shownTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              selected: filter.categoryIds.contains(c.id),
                              onSelected: (bool _) =>
                                  _update((FeedFilter f) => f.toggled(c.id)),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
              if (filter.isActive) ...<Widget>[
                const SizedBox(height: SageSpace.lg),
                TextButton(
                  onPressed: () {
                    _query.clear();
                    ref.read(feedFilterProvider.notifier).clear();
                  },
                  child: Text(tr('feed.filter.clear')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Active conditions as removable chips, and what the filter found.
class FeedFilterBar extends ConsumerWidget {
  const FeedFilterBar({required this.shown, required this.money, super.key});

  final List<FeedRecord> shown;
  final MoneyFormat money;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final FeedFilter filter = ref.watch(feedFilterProvider);
    final Map<String, Category> categories =
        ref.watch(categoryIndexProvider).value ?? const <String, Category>{};
    final FeedFilterController c = ref.read(feedFilterProvider.notifier);
    final SageColors sage = context.sage;

    Widget chip(String label, FeedFilter without) => Padding(
      padding: const EdgeInsets.only(right: SageSpace.xs),
      child: InputChip(
        label: Text(label),
        onDeleted: () => c.set(without),
        deleteButtonTooltipMessage: tr('common.clear'),
        onPressed: () => showFeedFilter(context),
        visualDensity: VisualDensity.compact,
      ),
    );

    return Container(
      color: sage.surface,
      padding: const EdgeInsets.fromLTRB(
        SageSpace.gutter,
        SageSpace.xs,
        SageSpace.gutter,
        SageSpace.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                if (filter.query.trim().isNotEmpty)
                  chip('"${filter.query.trim()}"', filter.copyWith(query: '')),
                if (filter.kind != FeedKind.all)
                  chip(
                    tr('feed.filter.kind.${filter.kind.name}'),
                    filter.copyWith(kind: FeedKind.all),
                  ),
                if (filter.status != FeedStatus.all)
                  chip(
                    statusLabel(filter.status, filter.kind),
                    filter.copyWith(status: FeedStatus.all),
                  ),
                for (final String id in filter.categoryIds)
                  chip(
                    categories[id]?.shownTitle ?? tr('category.none'),
                    filter.toggled(id),
                  ),
              ],
            ),
          ),
          Text(
            _found(shown, money),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// How many records matched, what they spent and what they brought.
String _found(List<FeedRecord> shown, MoneyFormat money) {
  Decimal spent = Decimal.zero;
  Decimal received = Decimal.zero;
  for (final FeedRecord r in shown) {
    final Decimal amount = r.amount ?? Decimal.zero;
    if (r.isIncome) {
      received += amount;
    } else {
      spent += amount;
    }
  }
  return <String>[
    plural('analytics.records', shown.length),
    if (spent > Decimal.zero) money.formatSigned(-spent),
    if (received > Decimal.zero) money.formatSigned(received),
  ].join(' · ');
}
