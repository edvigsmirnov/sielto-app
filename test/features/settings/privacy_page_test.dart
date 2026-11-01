import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/features/settings/privacy_page.dart';

void main() {
  test('policyBlocks drops the title and reads headings and bullets', () {
    expect(
      policyBlocks('# Title\n\nIntro line.\n\n## Part\n\n- one\n- two\n'),
      <({BlockKind kind, String text})>[
        (kind: BlockKind.paragraph, text: 'Intro line.'),
        (kind: BlockKind.heading, text: 'Part'),
        (kind: BlockKind.bullet, text: 'one'),
        (kind: BlockKind.bullet, text: 'two'),
      ],
    );
  });

  test('every translation of the policy has the same sections', () {
    int sections(String path) =>
        policyBlocks(File(path).readAsStringSync())
            .where((b) => b.kind == BlockKind.heading)
            .length;

    for (final FileSystemEntity file in Directory(
      'assets/privacy',
    ).listSync()) {
      expect(sections(file.path), sections('PRIVACY.md'), reason: file.path);
    }
  });
}
