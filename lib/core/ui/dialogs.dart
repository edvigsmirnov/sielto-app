import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';

/// The app's dialog: a centred title and body over [content], then [actions].
class SageDialog extends StatelessWidget {
  const SageDialog({
    this.title,
    this.body,
    this.content,
    this.actions,
    super.key,
  });

  final String? title;
  final String? body;
  final Widget? content;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return AlertDialog(
      title: title == null
          ? null
          : Text(title!, textAlign: TextAlign.center, style: text.titleMedium),
      // A phone narrows it.
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (body != null)
              Text(body!, textAlign: TextAlign.center, style: text.bodyMedium),
            if (body != null && content != null)
              const SizedBox(height: SageSpace.md),
            ?content,
            if (actions != null) ...<Widget>[
              const SizedBox(height: SageSpace.lg),
              actions!,
            ],
          ],
        ),
      ),
    );
  }
}

/// One of [choices], laid out by [ChoiceGrid]; null when dismissed.
Future<T?> choiceDialog<T>(
  BuildContext context, {
  required List<(String, T)> choices,
  String? title,
  String? body,
  int columns = 2,
  bool destructive = false,
  bool destructiveLast = false,
  bool primaryLast = false,
  bool dismissible = true,
}) => showDialog<T>(
  context: context,
  barrierDismissible: dismissible,
  builder: (BuildContext context) => PopScope(
    canPop: dismissible,
    child: SageDialog(
      title: title,
      body: body,
      actions: ChoiceGrid(
        columns: columns,
        destructive: destructive,
        destructiveLast: destructiveLast,
        primaryLast: primaryLast,
        choices: <(String, VoidCallback)>[
          for (final (String label, T value) in choices)
            (label, () => Navigator.of(context).pop(value)),
        ],
      ),
    ),
  ),
);

/// Returns false when dismissed.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  bool isDestructive = false,
}) async =>
    await choiceDialog<bool>(
      context,
      title: title,
      body: body,
      choices: <(String, bool)>[
        (tr('common.cancel'), false),
        (confirmLabel, true),
      ],
      destructiveLast: isDestructive,
      primaryLast: true,
    ) ??
    false;

/// Text to read, with a Close button.
Future<void> infoDialog(
  BuildContext context, {
  required String body,
  String? title,
}) => choiceDialog<void>(
  context,
  title: title,
  body: body,
  choices: <(String, void)>[(tr('common.close'), null)],
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

/// [columns] buttons a row; a short last row stretches to fill it.
class ChoiceGrid extends StatelessWidget {
  const ChoiceGrid({
    required this.choices,
    this.columns = 2,
    this.destructive = false,
    this.destructiveLast = false,
    this.primaryLast = false,
    super.key,
  });

  /// A null callback disables that choice.
  final List<(String, VoidCallback?)> choices;

  final int columns;

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
    Widget button((String, VoidCallback?) choice) {
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
      spacing: SageSpace.sm,
      children: <Widget>[
        for (int i = 0; i < choices.length; i += columns)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: SageSpace.sm,
              children: <Widget>[
                for (final (String, VoidCallback?) choice
                    in choices.skip(i).take(columns))
                  Expanded(child: button(choice)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Typed text, trimmed; null when cancelled. Without [allowEmpty] the
/// confirming button waits for some text.
Future<String?> textDialog(
  BuildContext context, {
  required String title,
  String? body,
  String initial = '',
  String? hint,
  String? confirmLabel,
  int? maxLength,
  int maxLines = 1,
  bool allowEmpty = true,
  TextInputType? keyboardType,
  TextCapitalization capitalization = TextCapitalization.words,
}) => showDialog<String>(
  context: context,
  builder: (BuildContext context) => _TextDialog(
    title: title,
    body: body,
    initial: initial,
    field: (TextEditingController controller, VoidCallback submit) => TextField(
      controller: controller,
      autofocus: true,
      maxLength: maxLength,
      maxLines: maxLines,
      minLines: 1,
      keyboardType: keyboardType,
      textCapitalization: capitalization,
      decoration: InputDecoration(hintText: hint, hintMaxLines: 2),
      onSubmitted: (String _) => submit(),
    ),
    confirmLabel: confirmLabel ?? tr('common.save'),
    allowEmpty: allowEmpty,
  ),
);

/// Owns its controller: the dialog outlives the future during its exit.
class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.body,
    required this.initial,
    required this.field,
    required this.confirmLabel,
    required this.allowEmpty,
  });

  final String title;
  final String? body;
  final String initial;
  final Widget Function(TextEditingController, VoidCallback submit) field;
  final String confirmLabel;
  final bool allowEmpty;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  )..addListener(() => setState(() {}));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _text => _controller.text.trim();

  bool get _ready => widget.allowEmpty || _text.isNotEmpty;

  void _submit() {
    if (_ready) Navigator.of(context).pop(_text);
  }

  @override
  Widget build(BuildContext context) => SageDialog(
    title: widget.title,
    body: widget.body,
    content: widget.field(_controller, _submit),
    actions: ChoiceGrid(
      choices: <(String, VoidCallback?)>[
        (tr('common.cancel'), () => Navigator.of(context).pop()),
        (widget.confirmLabel, _ready ? _submit : null),
      ],
      primaryLast: true,
    ),
  );
}

/// A destructive confirmation that stays disabled until [word] is typed.
Future<bool> typedConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String word,
  required String confirmLabel,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (BuildContext _) => _TypedConfirmDialog(
        title: title,
        body: body,
        word: word,
        confirmLabel: confirmLabel,
      ),
    ) ??
    false;

class _TypedConfirmDialog extends StatefulWidget {
  const _TypedConfirmDialog({
    required this.title,
    required this.body,
    required this.word,
    required this.confirmLabel,
  });

  final String title;
  final String body;
  final String word;
  final String confirmLabel;

  @override
  State<_TypedConfirmDialog> createState() => _TypedConfirmDialogState();
}

class _TypedConfirmDialogState extends State<_TypedConfirmDialog> {
  final TextEditingController _typed = TextEditingController();

  @override
  void initState() {
    super.initState();
    _typed.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool matches =
        _typed.text.trim().toLowerCase() == widget.word.trim().toLowerCase();
    return SageDialog(
      title: widget.title,
      body: widget.body,
      content: TextField(
        controller: _typed,
        autofocus: true,
        autocorrect: false,
      ),
      actions: ChoiceGrid(
        choices: <(String, VoidCallback?)>[
          (tr('common.cancel'), () => Navigator.of(context).pop(false)),
          (
            widget.confirmLabel,
            matches ? () => Navigator.of(context).pop(true) : null,
          ),
        ],
        destructiveLast: true,
        primaryLast: true,
      ),
    );
  }
}
