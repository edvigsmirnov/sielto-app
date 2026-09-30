import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/sage_widgets.dart';

class SheetAction<T> {
  const SheetAction(
    this.icon,
    this.label,
    this.value, {
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final T value;
  final bool destructive;
}

/// Actions in groups, divided by a hairline. Null when dismissed.
Future<T?> showActionSheet<T>(
  BuildContext context, {
  required String title,
  required List<List<SheetAction<T>>> groups,
}) => showModalBottomSheet<T>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  backgroundColor: context.sage.card,
  builder: (BuildContext sheet) {
    final List<List<SheetAction<T>>> shown = <List<SheetAction<T>>>[
      for (final List<SheetAction<T>> g in groups)
        if (g.isNotEmpty) g,
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: SageSpace.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SageSpace.gutter,
                0,
                SageSpace.gutter,
                SageSpace.sm,
              ),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(sheet).textTheme.titleMedium,
              ),
            ),
            for (int i = 0; i < shown.length; i++) ...<Widget>[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: SageSpace.gutter,
                    vertical: SageSpace.xs,
                  ),
                  child: Hairline(),
                ),
              for (final SheetAction<T> action in shown[i])
                _ActionRow<T>(action: action),
            ],
          ],
        ),
      ),
    );
  },
);

class _ActionRow<T> extends StatelessWidget {
  const _ActionRow({required this.action});

  final SheetAction<T> action;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final Color ink = action.destructive ? sage.danger : sage.accentStrong;
    return InkWell(
      onTap: () => Navigator.of(context).pop(action.value),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SageSpace.gutter,
          vertical: SageSpace.sm,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: action.destructive ? sage.dangerTint : sage.accentTint,
                shape: BoxShape.circle,
              ),
              child: Icon(action.icon, size: 20, color: ink),
            ),
            const SizedBox(width: SageSpace.md),
            Expanded(
              child: Text(
                action.label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: action.destructive ? sage.danger : sage.ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
