import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';

/// The only [Decimal]-to-double conversion: rounded first, display only.
class MoneyFormat {
  MoneyFormat({required this.locale, required this.currencyCode})
    : _format = NumberFormat.simpleCurrency(
        locale: locale,
        name: currencyCode,
        decimalDigits: _decimalDigits,
      ),
      _whole = NumberFormat.simpleCurrency(
        locale: locale,
        name: currencyCode,
        decimalDigits: 0,
      );

  static const int _decimalDigits = 2;

  final String locale;
  final String currencyCode;
  final NumberFormat _format;

  final NumberFormat _whole;

  String get symbol => _format.currencySymbol;

  String format(Decimal amount) =>
      _format.format(amount.round(scale: _decimalDigits).toDouble());

  /// Explicit `+` on positive values.
  String formatSigned(Decimal amount) {
    final String base = format(amount);
    return amount > Decimal.zero ? '+$base' : base;
  }

  /// Whole units.
  String short(Decimal amount) => _whole.format(amount.round().toDouble());

  /// [short] with an explicit sign.
  String shortSigned(Decimal amount) {
    if (amount == Decimal.zero) return _whole.format(0);
    final String base = short(amount.abs());
    return amount > Decimal.zero ? '+$base' : '-$base';
  }
}
