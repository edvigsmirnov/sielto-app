import 'package:drift/drift.dart' show Value;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/category_repository.dart';
import 'package:sielto/core/db/repositories/payment_repository.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/bulk_button.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/features/categories/category_colors.dart';
import 'package:sielto/features/categories/category_form_page.dart';
import 'package:sielto/features/categories/category_title.dart';
import 'package:sielto/features/payments/category_picker.dart';
import 'package:sielto/features/space/space_ledger.dart';

/// Categories: add, reorder, edit, soft-delete with undo. Long-press selects.
class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});

  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage> {
  Set<String> _selected = const <String>{};

  /// Whether the bulk button was pressed during this selection.
  bool _bulkSeen = false;

  void _toggle(String id) => setState(() {
    _selected = _selected.contains(id)
        ? (Set<String>.of(_selected)..remove(id))
        : <String>{..._selected, id};
    if (_selected.isEmpty) _bulkSeen = false;
  });

  void _clear() => setState(() {
    _selected = const <String>{};
    _bulkSeen = false;
  });

  @override
  Widget build(BuildContext context) {
    final List<Category> categories =
        ref.watch(spaceCategoriesProvider).value ?? const <Category>[];
    final bool selecting = _selected.isNotEmpty;

    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) _clear();
      },
      child: Scaffold(
        floatingActionButton: selecting
            ? BulkActionsButton(
                pulse: !_bulkSeen,
                tooltip: tr('feed.bulk.title'),
                onPressed: () {
                  setState(() => _bulkSeen = true);
                  _bulkActions(<Category>[
                    for (final Category c in categories)
                      if (_selected.contains(c.id)) c,
                  ]);
                },
              )
            : null,
        backgroundColor: context.sage.surface,
        appBar: AppBar(
          title: Text(tr('category.title')),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: tr('category.add'),
              onPressed: () => openCategoryForm(context),
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            Expanded(
              child: categories.isEmpty
                  ? EmptyState(message: tr('category.empty'))
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      padding: EdgeInsets.zero,
                      itemCount: categories.length,
                      itemBuilder: (BuildContext context, int index) =>
                          _CategoryTile(
                            key: ValueKey<String>(categories[index].id),
                            index: index,
                            category: categories[index],
                            selecting: selecting,
                            isSelected: _selected.contains(
                              categories[index].id,
                            ),
                            onLongPress: () => _toggle(categories[index].id),
                            onEdit: selecting
                                ? () => _toggle(categories[index].id)
                                : () => openCategoryForm(
                                    context,
                                    category: categories[index],
                                  ),
                            onDelete: () =>
                                _delete(context, ref, categories[index]),
                          ),
                      onReorderStart: (int index) =>
                          HapticFeedback.mediumImpact(),
                      onReorderItem: (int oldIndex, int newIndex) =>
                          _reorder(ref, categories, oldIndex, newIndex),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(SageSpace.gutter),
              child: DashedButton(
                label: '+ ${tr('category.add')}',
                onTap: () => openCategoryForm(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _bulkActions(List<Category> chosen) async {
    final bool? move = await showModalBottomSheet<bool>(
      context: context,
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: Text(
                tr(
                  'feed.bulk.selected',
                  namedArgs: <String, String>{'count': '${chosen.length}'},
                ),
                style: Theme.of(sheet).textTheme.titleSmall,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: Text(tr('category.moveRecords')),
              onTap: () => Navigator.of(sheet).pop(true),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(tr('common.delete')),
              onTap: () => Navigator.of(sheet).pop(false),
            ),
          ],
        ),
      ),
    );
    if (move == null || !mounted) return;
    final Repositories repos = ref.read(repositoriesProvider);

    List<Category> sources = chosen;
    if (move) {
      final CategoryChoice? target = await pickCategory(
        context,
        selectedId: null,
      );
      if (target == null) return;
      sources = <Category>[
        for (final Category c in chosen)
          if (c.id != target.category?.id) c,
      ];
      int moved = 0;
      for (final Category c in sources) {
        moved += await repos.payments.moveCategory(c.id, target.category?.id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'category.moved',
                namedArgs: <String, String>{'count': '$moved'},
              ),
            ),
          ),
        );
    }
    if (sources.isEmpty || !mounted) return;

    final bool confirmed = await confirmDialog(
      context,
      title: tr('category.deleteManyTitle'),
      body: tr(
        'category.deleteManyBody',
        namedArgs: <String, String>{
          'titles': sources.map((Category c) => c.shownTitle).join(', '),
        },
      ),
      confirmLabel: tr('common.delete'),
      isDestructive: true,
    );
    if (!confirmed) return;
    for (final Category c in sources) {
      await repos.categories.softDelete(c.id);
    }
    _clear();
    if (!mounted) return;
    showUndoSnackbar(
      context,
      message: tr(
        'feed.bulk.deleted',
        namedArgs: <String, String>{'count': '${sources.length}'},
      ),
      onUndo: () async {
        for (final Category c in sources) {
          await repos.categories.restore(c.id);
        }
      },
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Category category,
  ) async {
    final bool confirmed = await confirmDialog(
      context,
      title: tr('category.deleteTitle'),
      body: tr(
        'category.deleteBody',
        namedArgs: <String, String>{'title': category.shownTitle},
      ),
      confirmLabel: tr('common.delete'),
      isDestructive: true,
    );
    if (!confirmed) return;

    final CategoryRepository repo = ref.read(repositoriesProvider).categories;
    await repo.softDelete(category.id);
    if (!context.mounted) return;
    showUndoSnackbar(
      context,
      message: tr(
        'category.deleted',
        namedArgs: <String, String>{'title': category.shownTitle},
      ),
      onUndo: () => repo.restore(category.id),
    );
  }

  /// Renumbers the whole list. [newIndex] is already corrected for the removal.
  Future<void> _reorder(
    WidgetRef ref,
    List<Category> categories,
    int oldIndex,
    int newIndex,
  ) async {
    final List<Category> ordered = List<Category>.of(categories);
    final Category moved = ordered.removeAt(oldIndex);
    ordered.insert(newIndex, moved);

    final CategoryRepository repo = ref.read(repositoriesProvider).categories;
    await repo.db.transaction(() async {
      for (int i = 0; i < ordered.length; i++) {
        final int order = i * PaymentRepository.sortOrderGap;
        if (ordered[i].sortOrder == order) continue;
        await repo.updateAppearance(
          ordered[i].id,
          sortOrder: Value<int>(order),
        );
      }
    });
  }
}

/// Grip, mark, name, default type.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.index,
    required this.category,
    required this.onEdit,
    required this.onDelete,
    required this.onLongPress,
    required this.selecting,
    required this.isSelected,
    super.key,
  });

  final int index;
  final Category category;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onLongPress;
  final bool selecting;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;

    return Dismissible(
      key: ValueKey<String>('dismiss:${category.id}'),
      direction: selecting
          ? DismissDirection.none
          : DismissDirection.endToStart,
      background: Container(
        color: sage.dangerTint,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: SageSpace.lg),
        child: Icon(Icons.delete_outline, size: 20, color: sage.danger),
      ),
      confirmDismiss: (DismissDirection _) async {
        onDelete();
        // The query decides removal, so undo restores the row.
        return false;
      },
      child: InkWell(
        onTap: onEdit,
        onLongPress: () {
          HapticFeedback.mediumImpact();
          onLongPress();
        },
        child: Ink(
          color: isSelected ? sage.accentTint : Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              SageSpace.xs,
              SageSpace.xs,
              SageSpace.gutter,
              SageSpace.xs,
            ),
            child: Row(
              children: <Widget>[
                if (selecting)
                  const SizedBox(width: 48, height: 48)
                else
                  DragGrip(index: index),
                const SizedBox(width: SageSpace.xs),
                CategoryMark(color: category.color, icon: category.icon),
                const SizedBox(width: SageSpace.md),
                Expanded(
                  child: Text(
                    category.shownTitle,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: SageSpace.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: sage.canvas,
                    borderRadius: BorderRadius.circular(SageRadius.pill),
                  ),
                  child: Text(
                    tr('expenseType.${category.expenseType.name}'),
                    style: text.labelSmall?.copyWith(color: sage.inkSecondary),
                  ),
                ),
                const SizedBox(width: SageSpace.xs),
                Icon(Icons.chevron_right, size: 18, color: sage.inkLabel),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
