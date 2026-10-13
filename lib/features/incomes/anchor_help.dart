import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/layout.dart';
import 'package:sielto/core/ui/popover.dart';

/// Explains the anchor income.
Future<void> showAnchorHelp(BuildContext context) => isWide(context)
    ? showPopover<void>(
        context,
        builder: (BuildContext context) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              tr('income.anchorHelpTitle'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: SageSpace.sm),
            Text(
              tr('income.anchorHelpBody'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      )
    : showDialog<void>(
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
    onPressed: () => showAnchorHelp(context),
  );
}
