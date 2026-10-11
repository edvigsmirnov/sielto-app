import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sielto/core/theme/sage_tokens.dart';

/// A one-time code with its time left, Copy and Share.
class CodeCard extends StatelessWidget {
  const CodeCard({required this.code, required this.left, super.key});

  final String code;
  final Duration left;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      children: <Widget>[
        // Spelled out for screen readers.
        Semantics(
          label: code.split('').join(' '),
          excludeSemantics: true,
          child: SelectableText(
            code,
            textAlign: TextAlign.center,
            style: text.displaySmall?.copyWith(
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              letterSpacing: 4,
            ),
          ),
        ),
        const SizedBox(height: SageSpace.sm),
        Text(
          tr('devices.expiresIn', args: <String>[_clock(left)]),
          style: text.bodySmall,
        ),
        const SizedBox(height: SageSpace.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            OutlinedButton.icon(
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: Text(tr('devices.copy')),
              onPressed: () => _copy(context),
            ),
            const SizedBox(width: SageSpace.sm),
            OutlinedButton.icon(
              icon: const Icon(Icons.share_outlined, size: 18),
              label: Text(tr('devices.share')),
              onPressed: () =>
                  SharePlus.instance.share(ShareParams(text: code)),
            ),
          ],
        ),
      ],
    );
  }

  static String _clock(Duration left) =>
      '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}';

  Future<void> _copy(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: code));
    messenger.showSnackBar(SnackBar(content: Text(tr('devices.copied'))));
  }
}
