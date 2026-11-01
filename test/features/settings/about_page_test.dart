import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/features/settings/about_page.dart';

void main() {
  test('reflow joins wrapped lines but keeps numbered items apart', () {
    expect(
      reflow('A long\n  sentence.\n\nRULES:\n1. One \n   more.\n2. Two.\n'),
      <String>['A long sentence.', 'RULES:\n1. One more.\n2. Two.'],
    );
  });
}
