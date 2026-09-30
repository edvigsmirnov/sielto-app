import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';

/// Returns false when dismissed.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  bool isDestructive = false,
}) async {
  final bool? answer = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      final SageColors sage = context.sage;
      return AlertDialog(
        backgroundColor: sage.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SageRadius.card),
        ),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        content: Text(body, style: Theme.of(context).textTheme.bodyMedium),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: isDestructive ? sage.danger : sage.accentStrong,
            ),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return answer ?? false;
}

enum MandatoryChange { move, unpay, delete }

/// Confirmation before a mandatory payment is moved, unpaid or deleted.
Future<bool> confirmMandatory(BuildContext context, MandatoryChange change) =>
    confirmDialog(
      context,
      title: tr('payment.mandatoryConfirmTitle'),
      body: tr('payment.mandatoryConfirm.${change.name}'),
      confirmLabel: tr('common.continue'),
    );

const Duration undoWindow = Duration(seconds: 5);

/// Shown after a soft delete; the action restores the row.
void showUndoSnackbar(
  BuildContext context, {
  required String message,
  required VoidCallback onUndo,
}) {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: undoWindow,
        // The action slot takes only a label, so the button is in the content row.
        content: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: SageSpace.sm),
            _UndoCountdown(
              onUndo: () {
                messenger.hideCurrentSnackBar();
                onUndo();
              },
            ),
          ],
        ),
      ),
    );
}

/// Undo button inside a ring that empties over [undoWindow].
class _UndoCountdown extends StatefulWidget {
  const _UndoCountdown({required this.onUndo});

  final VoidCallback onUndo;

  @override
  State<_UndoCountdown> createState() => _UndoCountdownState();
}

class _UndoCountdownState extends State<_UndoCountdown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: undoWindow,
  )..reverse(from: 1);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color ink =
        Theme.of(context).snackBarTheme.actionTextColor ??
        context.sage.accentStrong;
    return TextButton(
      onPressed: widget.onUndo,
      style: TextButton.styleFrom(foregroundColor: ink),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 16,
            height: 16,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (BuildContext context, Widget? _) =>
                  CircularProgressIndicator(
                    value: _controller.value,
                    strokeWidth: 2,
                    color: ink,
                    backgroundColor: ink.withValues(alpha: 0.2),
                  ),
            ),
          ),
          const SizedBox(width: SageSpace.sm),
          Text(tr('common.undo')),
        ],
      ),
    );
  }
}
