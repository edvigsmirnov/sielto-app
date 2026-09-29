import 'package:intl/intl.dart';

/// Currency choices for Space creation. Any ISO 4217 code is valid.
abstract final class Currencies {
  static const List<String> common = <String>[
    'EUR',
    'USD',
    'GBP',
    'RUB',
    'CHF',
    'PLN',
    'CZK',
    'SEK',
    'NOK',
    'DKK',
    'TRY',
    'GEL',
    'RSD',
    'UAH',
    'KZT',
    'AMD',
    'AED',
    'CAD',
    'AUD',
    'JPY',
    'CNY',
    'INR',
    'BRL',
    'ILS',
  ];

  /// EUR when intl has no data for the locale.
  static String forLocale(String locale) {
    try {
      final String? name = NumberFormat.simpleCurrency(locale: locale)
          .currencyName;
      if (name != null && name.length == 3) return name;
    } on Exception {
      // No currency data for this locale.
    }
    return 'EUR';
  }

  /// "EUR €".
  static String label(String code, String locale) {
    try {
      final String symbol = NumberFormat.simpleCurrency(
        locale: locale,
        name: code,
      ).currencySymbol;
      return symbol == code ? code : '$code $symbol';
    } on Exception {
      return code;
    }
  }

  /// [detected] first, then [common] without duplicates.
  static List<String> offered(String detected) => <String>[
    detected,
    ...common.where((String code) => code != detected),
  ];
}
