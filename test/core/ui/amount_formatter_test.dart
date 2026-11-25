import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/core/ui/amount_formatter.dart';

void main() {
  /// Types [keys] one by one at the caret, from an empty field.
  TextEditingValue type(AmountFormatter formatter, String keys) {
    TextEditingValue value = TextEditingValue.empty;
    for (final String key in keys.split('')) {
      final int caret = value.selection.baseOffset.clamp(0, value.text.length);
      final String text =
          value.text.substring(0, caret) + key + value.text.substring(caret);
      value = formatter.formatEditUpdate(
        value,
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: caret + 1),
        ),
      );
    }
    return value;
  }

  TextEditingValue backspace(AmountFormatter formatter, String text, int at) =>
      formatter.formatEditUpdate(
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: at),
        ),
        TextEditingValue(
          text: text.substring(0, at - 1) + text.substring(at),
          selection: TextSelection.collapsed(offset: at - 1),
        ),
      );

  final AmountFormatter english = AmountFormatter('en');
  final AmountFormatter german = AmountFormatter('de');
  final AmountFormatter russian = AmountFormatter('ru');

  test('thousands group as digits are typed', () {
    expect(type(english, '1234567').text, '1,234,567');
    expect(type(german, '1234567').text, '1.234.567');
    expect(type(russian, '1234567').text, '1 234 567');
  });

  test('either separator starts the cents in the locale symbol', () {
    expect(type(english, '1234,5').text, '1,234.5');
    expect(type(german, '1234.56').text, '1.234,56');
    expect(type(german, '1234,56').text, '1.234,56');
  });

  test('a third cent digit, a second separator and letters are refused', () {
    expect(type(english, '12.345').text, '12.34');
    expect(type(german, '12,3,4').text, '12,34');
    expect(type(english, '12a').text, '12');
  });

  test('the caret stays after the digit typed', () {
    final TextEditingValue value = english.formatEditUpdate(
      const TextEditingValue(
        text: '1,234',
        selection: TextSelection.collapsed(offset: 2),
      ),
      const TextEditingValue(
        text: '1,5234',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    expect(value.text, '15,234');
    expect(value.selection.baseOffset, 2);
  });

  test('backspace over a group mark removes the digit before it', () {
    final TextEditingValue value = backspace(english, '1,234', 2);
    expect(value.text, '234');
    expect(value.selection.baseOffset, 0);
    expect(backspace(english, '1,234', 5).text, '123');
  });

  test('pasted amounts read in any locale', () {
    final TextEditingValue value = german.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: '1,234.50',
        selection: TextSelection.collapsed(offset: 8),
      ),
    );
    expect(value.text, '1.234,50');
  });

  test('text set in code takes the locale grouping', () {
    expect(german.normalize('1234.50'), '1.234,50');
    expect(english.normalize('40'), '40');
    expect(english.normalize('1,234.'), '1,234.');
    expect(english.normalize(''), '');
  });
}
