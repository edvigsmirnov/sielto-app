import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/layout.dart';

enum BlockKind { heading, bullet, paragraph }

typedef Block = ({BlockKind kind, String text});

/// Headings, `-` or `*` bullets and paragraphs, inline markup dropped. The
/// `#` title is left out unless [keepTitle]: the app bar carries it.
List<Block> markdownBlocks(String markdown, {bool keepTitle = false}) =>
    <Block>[
      for (final String raw in markdown.split('\n'))
        if (raw.trim() case final String line
            when line.isNotEmpty && (keepTitle || !line.startsWith('# ')))
          if (RegExp(r'^#{1,6} ').firstMatch(line) case final Match heading?)
            (
              kind: BlockKind.heading,
              text: dropInlineMarkup(line.substring(heading.end)),
            )
          else if (line.startsWith('- ') || line.startsWith('* '))
            (kind: BlockKind.bullet, text: dropInlineMarkup(line.substring(2)))
          else
            (
              kind: BlockKind.paragraph,
              text: dropInlineMarkup(line.replaceFirst(RegExp(r'^> ?'), '')),
            ),
    ];

/// [text] with links reduced to their text, autolinks to their URL,
/// emphasis and code marks removed, and runs of spaces collapsed.
String dropInlineMarkup(String text) => text
    .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (Match m) => m[1]!)
    .replaceAllMapped(RegExp(r'<(https?://[^>]*)>'), (Match m) => m[1]!)
    .replaceAll(RegExp(r'\*+(?=\S)|(?<=\S)\*+|`'), '')
    .replaceAll(RegExp(r' {2,}'), ' ');

/// [markdown] scrolled in a readable column, selectable as one text.
class PlainMarkdown extends StatelessWidget {
  const PlainMarkdown(this.markdown, {super.key, this.keepTitle = false});

  final String markdown;
  final bool keepTitle;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    final TextStyle? body = text.bodyMedium?.copyWith(color: sage.ink);

    Widget block(Block b) => switch (b.kind) {
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

    return SingleChildScrollView(
      padding: scrollPadding(context, const EdgeInsets.all(SageSpace.gutter)),
      child: Readable(
        child: SelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final Block b in markdownBlocks(
                markdown,
                keepTitle: keepTitle,
              ))
                block(b),
            ],
          ),
        ),
      ),
    );
  }
}
