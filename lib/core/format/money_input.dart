import 'package:decimal/decimal.dart';

/// Parses typed amounts. Accepts `,` and `.` as decimal separator in any
/// locale and strips group separators. Null when not a number.
Decimal? parseMoney(String input) {
  final String cleaned = input
      .replaceAll(RegExp(r'[\s  ]'), '')
      .replaceAll(',', '.');
  if (cleaned.isEmpty) return null;
  return Decimal.tryParse(cleaned);
}

/// A typed amount of zero or more, or above zero unless [allowZero]. Null
/// otherwise.
Decimal? parseAmount(String input, {bool allowZero = true}) {
  final Decimal? value = parseMoney(input);
  if (value == null || value < Decimal.zero) return null;
  if (!allowZero && value == Decimal.zero) return null;
  return value;
}

/// An amount for an input field: `2.50`, `40`.
String moneyText(Decimal? amount) => amount == null
    ? ''
    : amount.isInteger
    ? amount.toString()
    : amount.toStringAsFixed(2);
