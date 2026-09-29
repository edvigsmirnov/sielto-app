import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/core/format/money_input.dart';

void main() {
  Decimal? parse(String input) => parseMoney(input);

  test('plain digits parse', () {
    expect(parse('1200'), Decimal.fromInt(1200));
  });

  test('both decimal separators mean the same thing', () {
    expect(parse('12.50'), parse('12,50'));
    expect(parse('12,50'), Decimal.parse('12.5'));
  });

  test('group separators are stripped', () {
    expect(parse('1 200,50'), Decimal.parse('1200.5'));
    // Includes intl's non-breaking space.
    expect(parse('1 200.50'), Decimal.parse('1200.5'));
  });

  test('zero parses', () {
    // Zero is a dated to-do.
    expect(parse('0'), Decimal.zero);
  });

  test('exactness survives the classic float case', () {
    expect(parse('0.1')! + parse('0.2')!, Decimal.parse('0.3'));
  });

  test('empty and non-numeric text produce null', () {
    expect(parse(''), isNull);
    expect(parse('   '), isNull);
    expect(parse('abc'), isNull);
    expect(parse('12,,50'), isNull);
  });

  test('a negative value parses, and is the form s job to refuse', () {
    // Negative parses; the form rejects it.
    expect(parse('-5'), Decimal.fromInt(-5));
  });
}
