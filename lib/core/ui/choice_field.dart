import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/popover.dart';

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
    final _Picked<T>? picked = await showAdaptiveSheet<_Picked<T>>(
      context,
      dragHandle: true,
      builder: (BuildContext _) => _ChoiceSheet<T>(field: this),
    );
    if (picked != null && picked.value != value) onChanged(picked.value);
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

/// Wraps the choice so a null [T] is still a choice.
class _Picked<T> {
  const _Picked(this.value);

  final T value;
}

class _ChoiceSheet<T> extends StatelessWidget {
  const _ChoiceSheet({required this.field});

  final ChoiceField<T> field;

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
            child: SizedBox(
              width: double.infinity,
              child: Text(
                field.title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          Flexible(
            child: field.columns == null
                ? ListView.builder(
                    shrinkWrap: true,
                    itemCount: field.options.length,
                    itemBuilder: (BuildContext context, int index) {
                      final T option = field.options[index];
                      final bool selected = option == field.value;
                      return ListTile(
                        title: Text(field.labelOf(option)),
                        trailing: selected
                            ? Icon(
                                Icons.check,
                                color: context.sage.accentStrong,
                              )
                            : null,
                        selected: selected,
                        onTap: () =>
                            Navigator.of(context).pop(_Picked<T>(option)),
                      );
                    },
                  )
                : GridView.count(
                    shrinkWrap: true,
                    crossAxisCount: field.columns!,
                    padding: const EdgeInsets.symmetric(
                      horizontal: SageSpace.gutter,
                    ),
                    mainAxisSpacing: SageSpace.xs,
                    crossAxisSpacing: SageSpace.xs,
                    children: <Widget>[
                      for (final T option in field.options)
                        _GridCell(
                          label: field.labelOf(option),
                          selected: option == field.value,
                          onTap: () =>
                              Navigator.of(context).pop(_Picked<T>(option)),
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
