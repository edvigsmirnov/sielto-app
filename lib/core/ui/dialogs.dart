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
    builder: (BuildContext context) => AlertDialog(
      backgroundColor: context.sage.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SageRadius.card),
      ),
      title: Text(
        title,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: SageSpace.lg),
          ChoiceGrid(
            choices: <(String, VoidCallback)>[
              (tr('common.cancel'), () => Navigator.of(context).pop(false)),
              (confirmLabel, () => Navigator.of(context).pop(true)),
            ],
            destructiveLast: isDestructive,
            primaryLast: true,
          ),
        ],
      ),
    ),
  );
  return answer ?? false;
}

/// One of [options], as stacked full-width buttons. Null when dismissed.
Future<T?> chooseDialog<T>(
  BuildContext context, {
  required String title,
  required List<(String, T)> options,
  String? body,
}) => showDialog<T>(
  context: context,
  builder: (BuildContext context) => AlertDialog(
    backgroundColor: context.sage.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(SageRadius.card),
    ),
    title: Text(
      title,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleMedium,
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (body != null)
          Padding(
            padding: const EdgeInsets.only(bottom: SageSpace.sm),
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        for (final (String label, T value) in options)
          Padding(
            padding: const EdgeInsets.only(top: SageSpace.sm),
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(value),
              child: Text(label, textAlign: TextAlign.center),
            ),
          ),
      ],
    ),
  ),
);

/// Back asks before throwing away edits; [isDirty] is read on each press.
class DiscardGuard extends StatelessWidget {
  const DiscardGuard({required this.isDirty, required this.child, super.key});

  final bool Function() isDirty;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (bool didPop, Object? _) async {
      if (didPop) return;
      final NavigatorState navigator = Navigator.of(context);
      if (!isDirty() ||
          await confirmDialog(
            context,
            title: tr('common.discardTitle'),
            body: tr('common.discardBody'),
            confirmLabel: tr('common.discard'),
            isDestructive: true,
          )) {
        navigator.pop();
      }
    },
    child: child,
  );
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

/// Two buttons a row; an odd last one takes the whole row.
class ChoiceGrid extends StatelessWidget {
  const ChoiceGrid({
    required this.choices,
    this.destructive = false,
    this.destructiveLast = false,
    this.primaryLast = false,
    super.key,
  });

  final List<(String, VoidCallback)> choices;

  /// Every choice in the danger colour.
  final bool destructive;

  /// Only the last one.
  final bool destructiveLast;

  /// The last one is filled: the confirming action.
  final bool primaryLast;

  @override
  Widget build(BuildContext context) {
    final ButtonStyle danger = OutlinedButton.styleFrom(
      foregroundColor: context.sage.danger,
    );
    Widget button((String, VoidCallback) choice) {
      final bool last = identical(choice, choices.last);
      final bool red = destructive || (destructiveLast && last);
      final Widget label = Text(choice.$1, textAlign: TextAlign.center);
      if (primaryLast && last) {
        return FilledButton(
          onPressed: choice.$2,
          style: red
              ? FilledButton.styleFrom(
                  backgroundColor: context.sage.dangerTint,
                  foregroundColor: context.sage.danger,
                )
              : null,
          child: label,
        );
      }
      return OutlinedButton(
        onPressed: choice.$2,
        style: red ? danger : null,
        child: label,
      );
    }

    return Column(
      children: <Widget>[
        for (int i = 0; i < choices.length; i += 2)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : SageSpace.sm),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(child: button(choices[i])),
                  if (i + 1 < choices.length) ...<Widget>[
                    const SizedBox(width: SageSpace.sm),
                    Expanded(child: button(choices[i + 1])),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One line of text; null when cancelled.
Future<String?> textDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  int? maxLength,
}) => showDialog<String>(
  context: context,
  builder: (BuildContext context) => _TextDialog(
    title: title,
    initial: initial,
    hint: hint,
    maxLength: maxLength,
  ),
);

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.initial,
    required this.hint,
    required this.maxLength,
  });

  final String title;
  final String initial;
  final String? hint;
  final int? maxLength;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: context.sage.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(SageRadius.card),
    ),
    title: Text(
      widget.title,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleMedium,
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: _controller,
          autofocus: true,
          maxLength: widget.maxLength,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: widget.hint, hintMaxLines: 2),
          onSubmitted: (String value) => Navigator.of(context).pop(value),
        ),
        const SizedBox(height: SageSpace.lg),
        ChoiceGrid(
          choices: <(String, VoidCallback)>[
            (tr('common.cancel'), () => Navigator.of(context).pop()),
            (
              tr('common.save'),
              () => Navigator.of(context).pop(_controller.text),
            ),
          ],
          primaryLast: true,
        ),
      ],
    ),
  );
}
