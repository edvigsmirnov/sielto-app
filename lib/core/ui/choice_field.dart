import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/popover.dart';
import 'package:sielto/core/ui/sage_widgets.dart';

/// Shows [value]; a tap opens a sheet of [options] titled [title].
class ChoiceField<T> extends StatelessWidget {
  const ChoiceField({
    required this.value,
    required this.options,
    required this.labelOf,
    required this.title,
    required this.onChanged,
    this.columns,
    super.key,
  });

  final T value;
  final List<T> options;
  final String Function(T) labelOf;
  final String title;
  final ValueChanged<T> onChanged;

  /// Lays short options out in a grid of this many columns.
  final int? columns;

  Future<void> _pick(BuildContext context) async {
    final (T,)? picked = await pickChoice<T>(
      context,
      title: title,
      options: options,
      value: value,
      labelOf: labelOf,
      columns: columns,
    );
    if (picked != null && picked.$1 != value) onChanged(picked.$1);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(SageRadius.button),
      child: InputDecorator(
        decoration: const InputDecoration(
          suffixIcon: Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          labelOf(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    ),
  );
}

/// A sheet of [options] with [value] checked. The choice comes in a record,
/// so a null [T] is still a choice; null when dismissed.
Future<(T,)?> pickChoice<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required T value,
  required String Function(T) labelOf,
  int? columns,
}) => showAdaptiveSheet<(T,)>(
  context,
  dragHandle: true,
  builder: (BuildContext _) => _ChoiceSheet<T>(
    title: title,
    options: options,
    value: value,
    labelOf: labelOf,
    columns: columns,
  ),
);

class _ChoiceSheet<T> extends StatelessWidget {
  const _ChoiceSheet({
    required this.title,
    required this.options,
    required this.value,
    required this.labelOf,
    required this.columns,
  });

  final String title;
  final List<T> options;
  final T value;
  final String Function(T) labelOf;
  final int? columns;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.only(bottom: SageSpace.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SageSpace.gutter,
              0,
              SageSpace.gutter,
              SageSpace.sm,
            ),
            child: SheetTitle(title),
          ),
          Flexible(
            child: columns == null
                ? ListView.builder(
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (BuildContext context, int index) {
                      final T option = options[index];
                      final bool selected = option == value;
                      return ListTile(
                        title: Text(labelOf(option)),
                        trailing: selected
                            ? Icon(
                                Icons.check,
                                color: context.sage.accentStrong,
                              )
                            : null,
                        selected: selected,
                        onTap: () => Navigator.of(context).pop((option,)),
                      );
                    },
                  )
                : GridView.count(
                    shrinkWrap: true,
                    crossAxisCount: columns!,
                    padding: const EdgeInsets.symmetric(
                      horizontal: SageSpace.gutter,
                    ),
                    mainAxisSpacing: SageSpace.xs,
                    crossAxisSpacing: SageSpace.xs,
                    children: <Widget>[
                      for (final T option in options)
                        _GridCell(
                          label: labelOf(option),
                          selected: option == value,
                          onTap: () => Navigator.of(context).pop((option,)),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    ),
  );
}

class _GridCell extends StatelessWidget {
  const _GridCell({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? sage.accent : sage.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SageRadius.button),
          side: BorderSide(color: selected ? sage.accent : sage.border),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SageRadius.button),
          ),
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: selected ? sage.accentOn : null),
            ),
          ),
        ),
      ),
    );
  }
}
