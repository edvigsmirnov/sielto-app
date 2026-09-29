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
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/features/categories/category_colors.dart';
import 'package:sielto/features/categories/category_form_page.dart';
import 'package:sielto/features/categories/category_title.dart';
import 'package:sielto/features/space/space_ledger.dart';

/// Categories: add, reorder, edit, soft-delete with undo.
class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Category> categories =
        ref.watch(spaceCategoriesProvider).value ?? const <Category>[];

    return Scaffold(
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
                          onEdit: () => openCategoryForm(
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
    for (int i = 0; i < ordered.length; i++) {
      final int order = i * PaymentRepository.sortOrderGap;
      if (ordered[i].sortOrder == order) continue;
      await repo.updateAppearance(ordered[i].id, sortOrder: Value<int>(order));
    }
  }
}

/// Grip, mark, name, default type.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.index,
    required this.category,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final int index;
  final Category category;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;

    return Dismissible(
      key: ValueKey<String>('dismiss:${category.id}'),
      direction: DismissDirection.endToStart,
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
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SageSpace.gutter,
            vertical: SageSpace.md,
          ),
          child: Row(
            children: <Widget>[
              ReorderableDragStartListener(
                index: index,
                child: Icon(
                  Icons.drag_indicator,
                  size: 20,
                  color: sage.inkLabel,
                ),
              ),
              const SizedBox(width: SageSpace.md),
              CategoryMark(color: category.color, icon: category.icon),
              const SizedBox(width: SageSpace.md),
              Expanded(
                child: Text(
                  category.shownTitle,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
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
    );
  }
}
