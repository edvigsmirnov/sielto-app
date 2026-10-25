import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/features/sync/sync_controller.dart';

/// Letters in a device link or invite code.
const int codeLength = 8;

/// What went wrong with a code, for the reader.
String codeProblem(JoinResult result, {required String wrongCode}) =>
    tr(switch (result) {
      JoinResult.offlineMode ||
      JoinResult.noNetwork ||
      JoinResult.unlinked => 'storage.${result.name}',
      JoinResult.tooManyAttempts => 'devices.tooManyAttempts',
      JoinResult.spaceFull => 'members.joinFull',
      JoinResult.refused => 'devices.refusedHere',
      JoinResult.notAnswered => 'devices.notAnswered',
      _ => wrongCode,
    });

/// A code typed from another device or person: [body], the field, [problem]
/// and the button, which waits for all [codeLength] letters.
class CodeEntry extends StatefulWidget {
  const CodeEntry({
    required this.body,
    required this.action,
    required this.busyAction,
    required this.busy,
    required this.problem,
    required this.onSubmit,
    this.bodyAlign = TextAlign.start,
    super.key,
  });

  final String body;
  final String action;
  final String busyAction;
  final bool busy;
  final String? problem;
  final ValueChanged<String> onSubmit;
  final TextAlign bodyAlign;

  @override
  State<CodeEntry> createState() => _CodeEntryState();
}

class _CodeEntryState extends State<CodeEntry> {
  late final TextEditingController _code = TextEditingController()
    ..addListener(() => setState(() {}));

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  bool get _ready => !widget.busy && _code.text.trim().length == codeLength;

  void _submit() {
    if (_ready) widget.onSubmit(_code.text);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(widget.body, style: text.bodyMedium, textAlign: widget.bodyAlign),
        const SizedBox(height: SageSpace.lg),
        LabelledField(
          label: tr('devices.codeField'),
          child: TextField(
            controller: _code,
            enabled: !widget.busy,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            maxLength: codeLength,
            textCapitalization: TextCapitalization.characters,
            onSubmitted: (String _) => _submit(),
          ),
        ),
        if (widget.problem case final String problem) ...<Widget>[
          const SizedBox(height: SageSpace.sm),
          Semantics(
            liveRegion: true,
            child: Text(problem, style: text.bodyMedium),
          ),
        ],
        const SizedBox(height: SageSpace.lg),
        FilledButton(
          onPressed: _ready ? _submit : null,
          child: Text(widget.busy ? widget.busyAction : widget.action),
        ),
      ],
    );
  }
}

/// A one-time code with its time left, Copy and Share. Counts down to
/// [expires] by itself and calls [onExpired] when it gets there.
class CodeCard extends StatefulWidget {
  const CodeCard({
    required this.code,
    required this.expires,
    this.onExpired,
    super.key,
  });

  final String code;
  final DateTime expires;
  final VoidCallback? onExpired;

  @override
  State<CodeCard> createState() => _CodeCardState();
}

class _CodeCardState extends State<CodeCard> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (DateTime.now().isBefore(widget.expires)) return setState(() {});
      timer.cancel();
      widget.onExpired?.call();
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: widget.code));
    messenger.say(tr('devices.copied'));
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Duration left = widget.expires.difference(DateTime.now());
    final String clock =
        '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}';
    return Column(
      children: <Widget>[
        // Spelled out for screen readers.
        Semantics(
          label: widget.code.split('').join(' '),
          excludeSemantics: true,
          child: SelectableText(
            widget.code,
            textAlign: TextAlign.center,
            style: text.displaySmall?.copyWith(
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              letterSpacing: 4,
            ),
          ),
        ),
        const SizedBox(height: SageSpace.sm),
        Text(
          tr('devices.expiresIn', args: <String>[clock]),
          style: text.bodySmall,
        ),
        const SizedBox(height: SageSpace.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            OutlinedButton.icon(
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: Text(tr('devices.copy')),
              onPressed: _copy,
            ),
            const SizedBox(width: SageSpace.sm),
            OutlinedButton.icon(
              icon: const Icon(Icons.share_outlined, size: 18),
              label: Text(tr('devices.share')),
              onPressed: () =>
                  SharePlus.instance.share(ShareParams(text: widget.code)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Why there is no code, and a button for a new one.
class CodeRetry extends StatelessWidget {
  const CodeRetry({required this.message, required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Text(message, style: Theme.of(context).textTheme.bodyLarge),
      const SizedBox(height: SageSpace.lg),
      FilledButton(onPressed: onRetry, child: Text(tr('devices.newCode'))),
    ],
  );
}
