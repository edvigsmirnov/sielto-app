import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:sielto/core/format/currencies.dart';
import 'package:sielto/core/format/region_data.dart';

/// The device's region, which sets the default currency and how numbers are
/// written. The app language sets only the text.
abstract final class DeviceRegion {
  static Locale? _locale = _read();

  /// Null when the device names no country.
  static Locale? get locale => _locale;

  @visibleForTesting
  static set locale(Locale? value) => _locale = value;

  /// The intl locale for numbers: the [language] as spoken in the region when
  /// intl knows that pair, else the region's own language.
  static String numberLocale(Locale language) {
    final String? country = _locale?.countryCode;
    if (country == null) return language.toString();
    final List<String> candidates = <String>[
      '${language.languageCode}_$country',
      '${_locale!.languageCode}_$country',
      ?regionDefaults[country]?.$1,
    ];
    return candidates.firstWhere(
      _writesLatinDigits,
      orElse: () => language.languageCode,
    );
  }

  static bool _writesLatinDigits(String locale) =>
      NumberFormat.localeExists(locale) &&
      NumberFormat.decimalPattern(locale).symbols.ZERO_DIGIT == '0';

  /// The region's currency, else the one [language] implies.
  static String currency(Locale language) {
    final String? country = _locale?.countryCode;
    return regionDefaults[country]?.$2 ??
        Currencies.forLocale(language.toString());
  }

  static Locale? _read() {
    if (Platform.isLinux) return parse(_linuxLocaleName());
    if (Platform.isWindows) return parse(Platform.localeName);
    return PlatformDispatcher.instance.locale;
  }

  /// The format categories first: `LC_MESSAGES` and `LANGUAGE` set the text.
  static String _linuxLocaleName() {
    final Map<String, String> environment = Platform.environment;
    for (final String key in <String>['LC_ALL', 'LC_MONETARY', 'LC_NUMERIC']) {
      final String? value = environment[key];
      if (value != null && value.isNotEmpty) return value;
    }
    return environment['LANG'] ?? '';
  }

  /// `de_DE.UTF-8`, `de-DE`, `sr-Latn-RS`. Null without a country.
  @visibleForTesting
  static Locale? parse(String name) {
    final String bare = name.split(RegExp('[.@]')).first;
    final List<String> parts = bare.split(RegExp('[-_]'));
    final String? country = parts
        .skip(1)
        .where((String part) => RegExp(r'^[A-Z]{2}$').hasMatch(part))
        .firstOrNull;
    if (country == null) return null;
    return Locale(parts.first.toLowerCase(), country);
  }
}
