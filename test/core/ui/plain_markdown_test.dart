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
