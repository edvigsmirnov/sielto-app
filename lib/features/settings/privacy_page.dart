import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/detail_host.dart';
import 'package:sielto/core/ui/layout.dart';

/// `PRIVACY.md` in English, `assets/privacy/<code>.md` otherwise.
final _policyProvider = FutureProvider.family<String, String>((
  Ref ref,
  String language,
) async {
  if (language == 'en') return rootBundle.loadString('PRIVACY.md');
  try {
    return await rootBundle.loadString('assets/privacy/$language.md');
  } on FlutterError {
    return rootBundle.loadString('PRIVACY.md');
  }
});

enum BlockKind { heading, bullet, paragraph }

/// The Markdown subset the policy uses: `##`, `- ` and paragraphs. The `#`
/// title is left out, since the app bar carries it.
List<({BlockKind kind, String text})> policyBlocks(String markdown) =>
    <({BlockKind kind, String text})>[
      for (final String line in markdown.split('\n'))
        if (line.trim().isNotEmpty && !line.startsWith('# '))
          switch (line) {
            _ when line.startsWith('## ') => (
              kind: BlockKind.heading,
              text: line.substring(3),
            ),
            _ when line.startsWith('- ') => (
              kind: BlockKind.bullet,
              text: line.substring(2),
            ),
            _ => (kind: BlockKind.paragraph, text: line.trim()),
          },
    ];

class PrivacyPage extends ConsumerWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    final String? policy = ref
        .watch(_policyProvider(context.locale.languageCode))
        .value;
    final TextStyle? body = text.bodyMedium?.copyWith(color: sage.ink);

    Widget block(({BlockKind kind, String text}) b) => switch (b.kind) {
      BlockKind.heading => Padding(
        padding: const EdgeInsets.only(top: SageSpace.md, bottom: SageSpace.sm),
        child: Semantics(
          header: true,
          child: Text(
            b.text,
            style: text.titleMedium?.copyWith(color: sage.ink),
          ),
        ),
      ),
      BlockKind.bullet => Padding(
        padding: const EdgeInsets.only(bottom: SageSpace.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ExcludeSemantics(child: Text('•  ', style: body)),
            Expanded(child: Text(b.text, style: body)),
          ],
        ),
      ),
      BlockKind.paragraph => Padding(
        padding: const EdgeInsets.only(bottom: SageSpace.md),
        child: Text(b.text, style: body),
      ),
    };

    return Scaffold(
      backgroundColor: sage.surface,
      appBar: sageAppBar(context, title: Text(tr('about.privacy'))),
      body: policy == null
          ? const SizedBox.shrink()
          : SingleChildScrollView(
              padding: scrollPadding(
                context,
                const EdgeInsets.all(SageSpace.gutter),
              ),
              child: Readable(
                child: SelectionArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (final ({BlockKind kind, String text}) b
                          in policyBlocks(policy))
                        block(b),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
