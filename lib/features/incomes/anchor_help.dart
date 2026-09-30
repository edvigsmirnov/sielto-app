import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';

/// Explains the anchor income.
Future<void> showAnchorHelp(BuildContext context) => showDialog<void>(
  context: context,
  builder: (BuildContext context) => AlertDialog(
    backgroundColor: context.sage.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(SageRadius.card),
    ),
    title: Text(
      tr('income.anchorHelpTitle'),
      style: Theme.of(context).textTheme.titleMedium,
    ),
    content: Text(
      tr('income.anchorHelpBody'),
      style: Theme.of(context).textTheme.bodyMedium,
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(tr('common.close')),
      ),
    ],
  ),
);

class AnchorHelpButton extends StatelessWidget {
  const AnchorHelpButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(Icons.info_outline, size: 18, color: context.sage.inkLabel),
    tooltip: tr('income.anchorHelpTitle'),
    visualDensity: VisualDensity.compact,
    onPressed: () => showAnchorHelp(context),
  );
}
