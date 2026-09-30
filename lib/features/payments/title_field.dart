import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/sage_widgets.dart';

/// Payment title with autocomplete from this Space's earlier titles. Uses
/// [RawAutocomplete] with the form's controller.
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

  static const int minimumPrefix = 2;

  static const Duration debounce = Duration(milliseconds: 250);

  @override
  ConsumerState<TitleField> createState() => _TitleFieldState();
}

class _TitleFieldState extends ConsumerState<TitleField> {
  /// Kept across rebuilds; [RawAutocomplete] tracks focus through it.
  final FocusNode _focus = FocusNode();

  /// About four rows.
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
        // Debounce: a newer keystroke makes this call stale.
        await Future<void>.delayed(TitleField.debounce);
        if (widget.controller.text.trim() != prefix) {
          return const Iterable<String>.empty();
        }
        final List<String> matches = await ref
            .read(repositoriesProvider)
            .payments
            .titleSuggestions(widget.spaceId, prefix);
        // The exact typed text is not suggested.
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
