import 'dart:math';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:sielto/core/format/money_input.dart';

/// Groups thousands as an amount is typed and keeps the caret after the same
/// digit. A typed `.` or `,` starts the cents.
class AmountFormatter extends TextInputFormatter {
  AmountFormatter(String locale)
    : _whole = NumberFormat.decimalPattern(locale),
      _decimal = NumberFormat.decimalPattern(locale).symbols.DECIMAL_SEP;

  static const int maxWholeDigits = 12;
  static const int maxFractionDigits = 2;

  final NumberFormat _whole;
  final String _decimal;

  /// [text] from any source in this locale's separators; unchanged when it
  /// is not an amount.
  String normalize(String text) {
    final AmountDigits? digits = readAmount(text);
    if (digits == null || digits.negative) return text;
    return _render(digits.whole, digits.fraction).text;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String before = oldValue.text;
    final String after = newValue.text;
    if (before == after) return newValue;

    final int prefix = _commonPrefix(before, after);
    final int suffix = _commonSuffix(before, after, prefix);
    final String removed = before.substring(prefix, before.length - suffix);
    final String inserted = after.substring(prefix, after.length - suffix);

    String head = _units(before.substring(0, prefix));
    String tail = _units(before.substring(before.length - suffix));
    final String? typed = _typedUnits(inserted);
    if (typed == null) return oldValue;

    // Deleting a group mark deletes the digit beside it.
    if (inserted.isEmpty && removed.isNotEmpty && _units(removed).isEmpty) {
      final bool backspace = oldValue.selection.end == prefix + removed.length;
      if (backspace && head.isNotEmpty) {
        head = head.substring(0, head.length - 1);
      } else if (!backspace && tail.isNotEmpty) {
        tail = tail.substring(1);
      }
    }

    final String units = head + typed + tail;
    final int point = units.indexOf('.');
    if (point != units.lastIndexOf('.')) return oldValue;
    final String whole = point < 0 ? units : units.substring(0, point);
    final String? fraction = point < 0 ? null : units.substring(point + 1);
    if (whole.length > maxWholeDigits) return oldValue;
    if ((fraction?.length ?? 0) > maxFractionDigits) return oldValue;

    final ({String text, int zerosDropped}) rendered = _render(whole, fraction);
    final int caretUnits = max(
      0,
      head.length + typed.length - rendered.zerosDropped,
    );
    return TextEditingValue(
      text: rendered.text,
      selection: TextSelection.collapsed(
        offset: _offsetAfter(rendered.text, caretUnits),
      ),
    );
  }

  ({String text, int zerosDropped}) _render(String whole, String? fraction) {
    final String trimmed = whole.replaceFirst(RegExp('^0+(?=.)'), '');
    final String grouped = trimmed.isEmpty
        ? ''
        : _whole.format(int.parse(trimmed));
    return (
      text: fraction == null ? grouped : '$grouped$_decimal$fraction',
      zerosDropped: whole.length - trimmed.length,
    );
  }

  /// Digits, and `.` for this locale's decimal separator.
  String _units(String text) {
    final StringBuffer units = StringBuffer();
    for (final String char in text.split('')) {
      if (_isDigit(char)) units.write(char);
      if (char == _decimal) units.write('.');
    }
    return units.toString();
  }

  /// One typed separator starts the cents; pasted text reads as an amount.
  /// Null when [inserted] holds anything else.
  String? _typedUnits(String inserted) {
    if (inserted.isEmpty) return '';
    if (inserted == '.' || inserted == ',') return '.';
    final AmountDigits? digits = readAmount(inserted);
    if (digits == null || digits.negative) return null;
    final String? fraction = digits.fraction;
    return fraction == null ? digits.whole : '${digits.whole}.$fraction';
  }

  int _offsetAfter(String text, int units) {
    if (units == 0) return 0;
    int seen = 0;
    for (int i = 0; i < text.length; i++) {
      final String char = text[i];
      if (_isDigit(char) || char == _decimal) seen++;
      if (seen == units) return i + 1;
    }
    return text.length;
  }

  static bool _isDigit(String char) =>
      char.codeUnitAt(0) >= 0x30 && char.codeUnitAt(0) <= 0x39;

  static int _commonPrefix(String a, String b) {
    final int limit = min(a.length, b.length);
    int i = 0;
    while (i < limit && a[i] == b[i]) {
      i++;
    }
    return i;
  }

  static int _commonSuffix(String a, String b, int prefix) {
    final int limit = min(a.length, b.length) - prefix;
    int i = 0;
    while (i < limit && a[a.length - 1 - i] == b[b.length - 1 - i]) {
      i++;
    }
    return i;
  }
}
