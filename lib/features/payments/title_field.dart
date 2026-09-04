import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/sage_widgets.dart';

/// The payment title, completing on what this Space has been charged before
/// (spec 8.2).
///
/// Half of the fragmentation defence: Analytics level 2 groups by free text, so
/// the cheapest fix is to stop a second spelling of "Klarna" from being typed.
/// The other half is the `lower(trim(title))` grouping itself.
///
/// [RawAutocomplete] rather than `Autocomplete`, because the form owns the
/// controller — it is loaded from the record and read back on save, and the
/// convenience widget insists on making its own.
class TitleField extends ConsumerStatefulWidget {
  const TitleField({
    required this.controller,
    required this.spaceId,
    this.enabled = true,
    super.key,
  });

  final TextEditingController controller;
  final String spaceId;
  final bool enabled;

  /// Below this a prefix matches most of the Space, and the list is noise
  /// rather than a shortcut.
  static const int minimumPrefix = 2;

  @override
  ConsumerState<TitleField> createState() => _TitleFieldState();
}

class _TitleFieldState extends ConsumerState<TitleField> {
  /// Owned here, not built in `build`: [RawAutocomplete] needs the same node
  /// across rebuilds to know whether the field still has focus.
  final FocusNode _focus = FocusNode();

  /// How tall the suggestion list may grow before it scrolls. Four rows leaves
  /// the amount field under it visible.
  static const double _maxOverlayHeight = 200;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;

    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: (TextEditingValue value) async {
        final String prefix = value.text.trim();
        if (prefix.length < TitleField.minimumPrefix) {
          return const Iterable<String>.empty();
        }
        final List<String> matches = await ref
            .read(repositoriesProvider)
            .payments
            .titleSuggestions(widget.spaceId, prefix);
        // What was just typed is not a suggestion: offering it back is a row
        // that does nothing.
        return matches.where(
          (String m) => m.toLowerCase() != prefix.toLowerCase(),
        );
      },
      onSelected: (String selection) => widget.controller.text = selection,
      fieldViewBuilder:
          (
            BuildContext context,
            TextEditingController field,
            FocusNode focus,
            VoidCallback onSubmitted,
          ) => TextField(
            controller: field,
            focusNode: focus,
            enabled: widget.enabled,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            onSubmitted: (String _) => onSubmitted(),
          ),
      optionsViewBuilder:
          (
            BuildContext context,
            void Function(String) onSelected,
            Iterable<String> options,
          ) => Material(
            color: sage.card,
            elevation: 4,
            borderRadius: BorderRadius.circular(SageRadius.input),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: _maxOverlayHeight),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (BuildContext _, int _) => const Hairline(),
                itemBuilder: (BuildContext context, int index) {
                  final String option = options.elementAt(index);
                  return InkWell(
                    onTap: () => onSelected(option),
                    child: Padding(
                      padding: const EdgeInsets.all(SageSpace.md),
                      child: Text(
                        option,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
    );
  }
}
