import 'package:decimal/decimal.dart';

/// Typed amount split into its digits. [fraction] is null without a decimal
/// separator; [whole] may be empty, as in `,5`.
typedef AmountDigits = ({bool negative, String whole, String? fraction});

final RegExp _groupMarks = RegExp('[\\s  ’\']');
final RegExp _amountChars = RegExp(r'^-?[\d.,]*$');
final RegExp _separator = RegExp('[.,]');

/// Reads typed text in any locale. The last `.` or `,` is the decimal
/// separator when at most two digits follow it; the others group thousands.
AmountDigits? readAmount(String input) {
  final String cleaned = input.replaceAll(_groupMarks, '');
  if (cleaned.isEmpty || !_amountChars.hasMatch(cleaned)) return null;
  if (cleaned.contains(RegExp('[.,]{2}'))) return null;
  final bool negative = cleaned.startsWith('-');
  final String unsigned = negative ? cleaned.substring(1) : cleaned;
  final int last = unsigned.lastIndexOf(_separator);
  final bool hasFraction = last >= 0 && unsigned.length - last - 1 <= 2;
  final String whole = (hasFraction ? unsigned.substring(0, last) : unsigned)
      .replaceAll(_separator, '');
  final String? fraction = hasFraction ? unsigned.substring(last + 1) : null;
  if (whole.isEmpty && (fraction == null || fraction.isEmpty)) return null;
  return (negative: negative, whole: whole, fraction: fraction);
}

/// Parses typed amounts, grouped or not, with `,` or `.` as decimal
/// separator. Null when not a number.
Decimal? parseMoney(String input) {
  final AmountDigits? digits = readAmount(input);
  if (digits == null) return null;
  final String sign = digits.negative ? '-' : '';
  final String whole = digits.whole.isEmpty ? '0' : digits.whole;
  final String fraction = digits.fraction ?? '';
  return Decimal.tryParse(
    fraction.isEmpty ? '$sign$whole' : '$sign$whole.$fraction',
  );
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
