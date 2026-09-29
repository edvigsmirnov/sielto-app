import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';

/// What an anchor income is, in plain words (spec 4.7).
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

/// Says so when an income has just become the anchor, with the way to the
/// explanation. Survives the form closing: the messenger and the navigator
/// are the app's.
void announceAnchor(BuildContext context, String title) {
  final NavigatorState navigator = Navigator.of(context);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          tr(
            'income.becameAnchor',
            namedArgs: <String, String>{'title': title},
          ),
        ),
        action: SnackBarAction(
          label: tr('income.anchorHelpAction'),
          onPressed: () => showAnchorHelp(navigator.context),
        ),
      ),
    );
}

/// The "i" beside an anchor badge or hint.
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
