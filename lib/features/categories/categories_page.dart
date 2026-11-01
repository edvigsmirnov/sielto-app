import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/category_repository.dart';
import 'package:sielto/core/db/repositories/payment_repository.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/action_sheet.dart';
import 'package:sielto/core/ui/bulk_button.dart';
import 'package:sielto/core/ui/detail_host.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/core/ui/layout.dart';
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

  void _toggle(String id) => setState(() {
    _selected = _selected.contains(id)
        ? (Set<String>.of(_selected)..remove(id))
        : <String>{..._selected, id};
  });

  void _clear() => setState(() => _selected = const <String>{});

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
                tooltip: tr('feed.bulk.title'),
                onPressed: () => _bulkActions(<Category>[
                  for (final Category c in categories)
                    if (_selected.contains(c.id)) c,
                ]),
              )
            : null,
        backgroundColor: context.sage.surface,
        appBar: sageAppBar(context, title: Text(tr('category.title'))),
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
                            onDelete: () => deleteCategories(
                              context,
                              ref,
                              <Category>[categories[index]],
                            ),
                          ),
                      onReorderStart: (int index) =>
                          HapticFeedback.mediumImpact(),
                      onReorderItem: (int oldIndex, int newIndex) =>
                          _reorder(categories, oldIndex, newIndex),
                    ),
            ),
            // The actions button takes its place while selecting.
            if (!selecting)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(SageSpace.gutter),
                  child: DashedButton(
                    label: '+ ${tr('category.add')}',
                    onTap: () => openCategoryForm(context),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// [newIndex] is already corrected for the removal.
  void _reorder(List<Category> categories, int oldIndex, int newIndex) {
    final List<Category> ordered = List<Category>.of(categories);
    ordered.insert(newIndex, ordered.removeAt(oldIndex));
    ref.read(repositoriesProvider).categories.reorder(ordered);
  }

  Future<void> _bulkActions(List<Category> chosen) async {
    final bool? move = await showActionSheet<bool>(
      context,
      title: tr(
        'feed.bulk.selected',
        namedArgs: <String, String>{'count': '${chosen.length}'},
      ),
      groups: <List<SheetAction<bool>>>[
        <SheetAction<bool>>[
          SheetAction<bool>(
            Icons.drive_file_move_outline,
            tr('category.moveRecords'),
            true,
          ),
        ],
        <SheetAction<bool>>[
          SheetAction<bool>(
            Icons.delete_outline,
            tr('common.delete'),
            false,
            destructive: true,
          ),
        ],
      ],
    );
    if (move == null || !mounted) return;
    final bool deleted = move
        ? await moveRecords(context, ref, chosen)
        : await deleteCategories(context, ref, chosen);
    if (deleted && mounted) _clear();
  }
}

/// Moves every payment of [from] into a category the reader picks, then
/// deletes the ones it came from, asking first unless [confirmed]. True when
/// they were deleted.
Future<bool> moveRecords(
  BuildContext context,
  WidgetRef ref,
  List<Category> from, {
  bool confirmed = false,
}) async {
  final CategoryChoice? target = await pickCategory(
    context,
    selectedId: from.length == 1 ? from.single.id : null,
  );
  if (target == null || !context.mounted) return false;
  final List<Category> sources = <Category>[
    for (final Category c in from)
      if (c.id != target.category?.id) c,
  ];
  if (sources.isEmpty) return false;
  final int moved = await ref
      .read(repositoriesProvider)
      .payments
      .moveCategories(<String>[
        for (final Category c in sources) c.id,
      ], target.category?.id);
  if (!context.mounted) return false;
  ScaffoldMessenger.of(
    context,
  ).say(tr('category.moved', namedArgs: <String, String>{'count': '$moved'}));
  return deleteCategories(context, ref, sources, confirmed: confirmed);
}

enum _Delete { moveFirst, delete }

/// Deletes [categories] with an undo, asking first unless [confirmed]. When
/// they hold entries, the reader may move those first. False when declined.
Future<bool> deleteCategories(
  BuildContext context,
  WidgetRef ref,
  List<Category> categories, {
  bool confirmed = false,
}) async {
  final bool one = categories.length == 1;
  if (!confirmed) {
    final PaymentRepository payments = ref.read(repositoriesProvider).payments;
    bool used = false;
    for (final Category c in categories) {
      used = used || await payments.anyVisibleInCategory(c.id);
    }
    if (!context.mounted) return false;
    final _Delete? choice = await choiceDialog<_Delete?>(
      context,
      title: tr(one ? 'category.deleteTitle' : 'category.deleteManyTitle'),
      body: one
          ? tr(
              'category.deleteBody',
              namedArgs: <String, String>{
                'title': categories.single.shownTitle,
              },
            )
          : tr(
              'category.deleteManyBody',
              namedArgs: <String, String>{
                'titles': categories
                    .map((Category c) => c.shownTitle)
                    .join(', '),
              },
            ),
      columns: used ? 1 : 2,
      choices: <(String, _Delete?)>[
        (tr('common.cancel'), null),
        if (used) (tr('category.moveFirst'), _Delete.moveFirst),
        (tr('common.delete'), _Delete.delete),
      ],
      destructiveLast: true,
      primaryLast: true,
    );
    if (choice == null || !context.mounted) return false;
    if (choice == _Delete.moveFirst) {
      return moveRecords(context, ref, categories, confirmed: true);
    }
  }
  final CategoryRepository repo = ref.read(repositoriesProvider).categories;
  final List<String> ids = <String>[for (final Category c in categories) c.id];
  await repo.setDeleted(ids, deleted: true);
  if (context.mounted) {
    showUndoSnackbar(
      context,
      message: one
          ? tr(
              'category.deleted',
              namedArgs: <String, String>{
                'title': categories.single.shownTitle,
              },
            )
          : tr(
              'feed.bulk.deleted',
              namedArgs: <String, String>{'count': '${categories.length}'},
            ),
      onUndo: () => repo.setDeleted(ids, deleted: false),
    );
  }
  return true;
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
      direction: selecting || desktopInput
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
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          if (!selecting)
            const SingleActivator(LogicalKeyboardKey.delete): onDelete,
        },
        child: InkWell(
          onTap: onEdit,
          onSecondaryTap: onLongPress,
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
                    SizedBox.square(
                      dimension: kMinInteractiveDimension,
                      child: Icon(
                        isSelected
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        color: isSelected ? sage.accentStrong : sage.inkLabel,
                      ),
                    )
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
                  Tag(
                    tr('expenseType.${category.expenseType.name}'),
                    ink: sage.inkSecondary,
                    fill: sage.canvas,
                  ),
                  const SizedBox(width: SageSpace.xs),
                  Icon(Icons.chevron_right, size: 18, color: sage.inkLabel),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
