import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

@immutable
class AppLocale {
  const AppLocale(this.locale, this.name);

  final Locale locale;

  /// The language's own name, never translated.
  final String name;
}

/// Offered locales. To add a language: add `assets/translations/<code>.json`
/// and an entry in [shipped].
abstract final class AppLocales {
  static const Locale en = Locale('en');
  static const Locale ru = Locale('ru');

  /// Pseudo-accented English for layout testing. See `PseudoAssetLoader`.
  static const Locale pseudo = Locale('en', 'XA');

  static const Locale fallback = en;

  static const String path = 'assets/translations';

  /// In picker order.
  static const List<AppLocale> shipped = <AppLocale>[
    AppLocale(en, 'English'),
    AppLocale(ru, 'Русский'),
  ];

  /// [shipped], plus the pseudolocale in debug builds.
  static List<AppLocale> get offered => <AppLocale>[
    ...shipped,
    if (kDebugMode) const AppLocale(pseudo, 'Pseudolocale'),
  ];

  static List<Locale> get supported =>
      offered.map((AppLocale l) => l.locale).toList(growable: false);

  /// Exact match, else the same language without a country, else [fallback].
  /// Entries with a country are skipped in the second step.
  static AppLocale resolve(Locale locale) {
    final List<AppLocale> all = offered;
    for (final AppLocale l in all) {
      if (l.locale == locale) return l;
    }
    for (final AppLocale l in all) {
      if (l.locale.countryCode == null &&
          l.locale.languageCode == locale.languageCode) {
        return l;
      }
    }
    return all.firstWhere((AppLocale l) => l.locale == fallback);
  }
}
