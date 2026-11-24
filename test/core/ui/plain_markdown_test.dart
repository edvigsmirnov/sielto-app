import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/core/ui/plain_markdown.dart';

void main() {
  test('markdownBlocks drops the title and reads headings and bullets', () {
    expect(
      markdownBlocks(
        '# Title\r\n\r\nIntro line.\n\n## Part\n\n- one\n* two\n### Fixes\n',
      ),
      <Block>[
        (kind: BlockKind.paragraph, text: 'Intro line.'),
        (kind: BlockKind.heading, text: 'Part'),
        (kind: BlockKind.bullet, text: 'one'),
        (kind: BlockKind.bullet, text: 'two'),
        (kind: BlockKind.heading, text: 'Fixes'),
      ],
    );
  });

  test('markdownBlocks keeps the title on request and drops inline markup', () {
    expect(
      markdownBlocks(
        '# Licence 1.0\n\n<https://example.com/l>\n\n'
        'See [Notices](#notices) for `Required Notice:` lines.\n'
        '> Required Notice: Example\n'
        '***As is, no warranty.***  The **licensor** is 5 * 3.\n',
        keepTitle: true,
      ),
      <Block>[
        (kind: BlockKind.heading, text: 'Licence 1.0'),
        (kind: BlockKind.paragraph, text: 'https://example.com/l'),
        (
          kind: BlockKind.paragraph,
          text: 'See Notices for Required Notice: lines.',
        ),
        (kind: BlockKind.paragraph, text: 'Required Notice: Example'),
        (
          kind: BlockKind.paragraph,
          text: 'As is, no warranty. The licensor is 5 * 3.',
        ),
      ],
    );
  });

  test('every translation of the privacy policy has the same sections', () {
    int sections(String path) =>
        markdownBlocks(File(path).readAsStringSync())
            .where((Block b) => b.kind == BlockKind.heading)
            .length;

    for (final FileSystemEntity file in Directory(
      'assets/privacy',
    ).listSync()) {
      expect(sections(file.path), sections('PRIVACY.md'), reason: file.path);
    }
  });
}
