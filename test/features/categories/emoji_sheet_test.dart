import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/features/categories/emoji_sheet.dart';

void main() {
  test('a typed icon is offered only when it is all emoji', () {
    for (final String s in <String>[
      '☕',
      '☕🍰',
      '🇩🇪✈️',
      '✈',
      '👨‍👩‍👧',
      '👍🏽',
    ]) {
      expect(isEmojiOnly(s), isTrue, reason: s);
    }
    for (final String s in <String>['a', '1', '☕a', '#']) {
      expect(isEmojiOnly(s), isFalse, reason: s);
    }
  });
}
