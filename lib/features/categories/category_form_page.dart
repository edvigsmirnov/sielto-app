import 'package:drift/drift.dart' show Value;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/category_repository.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/detail_host.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/core/ui/form_fields.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/categories/category_colors.dart';
import 'package:sielto/features/categories/category_icons.dart';
import 'package:sielto/features/categories/category_title.dart';
import 'package:sielto/features/categories/emoji_sheet.dart';
import 'package:sielto/features/payments/category_picker.dart';

/// Add or edit a category.
Future<void> openCategoryForm(BuildContext context, {Category? category}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => CategoryFormPage(category: category),
      ),
    );

class CategoryFormPage extends ConsumerStatefulWidget {
  const CategoryFormPage({this.category, super.key});

  final Category? category;

  @override
  ConsumerState<CategoryFormPage> createState() => _CategoryFormPageState();
}

class _CategoryFormPageState extends ConsumerState<CategoryFormPage> {
  late final TextEditingController _title = TextEditingController(
    text: widget.category?.shownTitle ?? '',
  );
  late String? _color = widget.category?.color ?? categoryPalette.first;
  late String? _icon = sanitiseCategoryIcon(widget.category?.icon);
  late ExpenseType _type = widget.category?.expenseType ?? ExpenseType.variable;

  /// Null until the freeze check runs; the title field stays disabled.
  bool? _canRename;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
    _checkRename();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _checkRename() async {
    final Category? existing = widget.category;
    if (existing == null) {
      setState(() => _canRename = true);
      return;
    }
    final bool allowed = await ref
        .read(repositoriesProvider)
        .categories
        .canRename(existing.id);
    if (mounted) setState(() => _canRename = allowed);
  }

  Future<void> _save() async {
    try {
      await _write();
    } on CategoryTitleTaken {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tr('category.titleTaken'))));
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _write() async {
    final CategoryRepository repo = ref.read(repositoriesProvider).categories;
    final Category? existing = widget.category;

    if (existing == null) {
      await repo.create(
        spaceId: ref.read(currentSpaceProvider)!.id,
        title: _title.text,
        color: _color,
        icon: _icon,
        expenseType: _type,
      );
    } else {
      // The title is editable only while no visible payment uses the category.
      await repo.updateAppearance(
        existing.id,
        color: Value<String?>(_color),
        icon: Value<String?>(_icon),
        expenseType: Value<ExpenseType>(_type),
      );
      if ((_canRename ?? false) && _title.text.trim() != existing.shownTitle) {
        await repo.rename(existing.id, _title.text);
      }
    }
  }

  Future<void> _moveRecords(Category from) async {
    final CategoryChoice? choice = await pickCategory(
      context,
      selectedId: from.id,
    );
    if (choice == null || choice.category?.id == from.id || !mounted) return;

    final Repositories repos = ref.read(repositoriesProvider);
    final int moved = await repos.payments.moveCategory(
      from.id,
      choice.category?.id,
    );
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
    if (moved == 0) return;

    final bool delete = await confirmDialog(
      context,
      title: tr('category.deleteTitle'),
      body: tr(
        'category.deleteBody',
        namedArgs: <String, String>{'title': from.shownTitle},
      ),
      confirmLabel: tr('common.delete'),
      isDestructive: true,
    );
    if (!delete) return;
    await repos.categories.softDelete(from.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickCustomIcon() async {
    final String? cleaned = sanitiseCategoryIcon(await pickEmoji(context));
    if (cleaned != null) setState(() => _icon = cleaned);
  }

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    final Category? existing = widget.category;
    final bool renameAllowed = _canRename ?? false;
    final String? custom = categoryIconChoices.contains(_icon) ? null : _icon;

    return Scaffold(
      backgroundColor: sage.surface,
      appBar: sageAppBar(
        context,
        title: Text(existing?.shownTitle ?? tr('category.add')),
      ),
      bottomNavigationBar: FormActionBar(
        child: FilledButton(
          onPressed: _title.text.trim().isEmpty ? null : _save,
          child: Text(tr('common.save')),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SageSpace.formGutter),
          children: <Widget>[
            LabelledField(
              label: tr('category.fieldTitle'),
              child: TextField(
                controller: _title,
                enabled: renameAllowed,
                inputFormatters: titleLimit,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  prefixIcon: _canRename == false
                      ? Icon(Icons.lock_outline, size: 18, color: sage.inkLabel)
                      : null,
                ),
              ),
            ),
            if (_canRename == false)
              Padding(
                padding: const EdgeInsets.only(top: SageSpace.xs),
                child: Text(
                  tr('category.titleFrozen'),
                  style: text.bodySmall?.copyWith(color: sage.warning),
                ),
              ),

            const SizedBox(height: SageSpace.lg),
            FieldLabel(tr('category.fieldColor')),
            _EvenWrap(
              runSpacing: 0,
              children: <Widget>[
                for (final (int i, String hex) in categoryPalette.indexed)
                  _Swatch(
                    label: tr('category.colorN', args: <String>['${i + 1}']),
                    hex: hex,
                    selected: _color == hex,
                    onTap: () => setState(() => _color = hex),
                  ),
              ],
            ),

            const SizedBox(height: SageSpace.lg),
            FieldLabel(tr('category.fieldIcon')),
            _EvenWrap(
              runSpacing: SageSpace.xs,
              children: <Widget>[
                for (final String glyph in categoryIconChoices)
                  _IconChoice(
                    label: glyph,
                    glyph: glyph,
                    selected: _icon == glyph,
                    onTap: () => setState(() => _icon = glyph),
                  ),
                _IconChoice(
                  label: tr('category.customIcon'),
                  glyph: custom ?? '+',
                  selected: custom != null,
                  onTap: _pickCustomIcon,
                ),
              ],
            ),

            const SizedBox(height: SageSpace.lg),
            LabelledField(
              label: tr('category.fieldDefaultType'),
              child: SegmentedChoice<ExpenseType>(
                values: ExpenseType.values,
                selected: _type,
                labelOf: (ExpenseType t) => tr('expenseType.${t.name}'),
                onChanged: (ExpenseType t) => setState(() => _type = t),
              ),
            ),

            if (existing != null) ...<Widget>[
              const SizedBox(height: SageSpace.xl),
              OutlinedButton.icon(
                icon: const Icon(Icons.drive_file_move_outline, size: 20),
                label: Text(tr('category.moveRecords')),
                onPressed: () => _moveRecords(existing),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Colour disc showing the chosen icon.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.label,
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: SizedBox.square(
        dimension: kMinInteractiveDimension,
        child: Center(
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: parseCategoryColor(hex),
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? context.sage.ink : Colors.transparent,
                width: 2,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.label,
    required this.glyph,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String glyph;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SageRadius.button),
        child: Container(
          width: kMinInteractiveDimension,
          height: kMinInteractiveDimension,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sage.card,
            borderRadius: BorderRadius.circular(SageRadius.button),
            border: Border.all(
              color: selected ? sage.accentStrong : sage.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            glyph,
            style: const TextStyle(
              fontSize: 18,
              fontFamilyFallback: emojiFonts,
            ),
          ),
        ),
      ),
    );
  }
}

/// 48 dp items spread so the rows run from edge to edge.
class _EvenWrap extends StatelessWidget {
  const _EvenWrap({required this.children, required this.runSpacing});

  final List<Widget> children;
  final double runSpacing;

  static const double _gap = SageSpace.xs;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints box) {
      const double size = kMinInteractiveDimension;
      final int perRow = ((box.maxWidth + _gap) / (size + _gap)).floor();
      final double spacing = perRow < 2
          ? _gap
          : (box.maxWidth - perRow * size) / (perRow - 1);
      return Wrap(spacing: spacing, runSpacing: runSpacing, children: children);
    },
  );
}
