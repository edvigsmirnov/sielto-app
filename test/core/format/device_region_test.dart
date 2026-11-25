import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/core/format/device_region.dart';
import 'package:sielto/core/format/money_format.dart';

void main() {
  tearDown(() => DeviceRegion.locale = null);

  String money(Locale language, String currency) => MoneyFormat(
    locale: DeviceRegion.numberLocale(language),
    currencyCode: currency,
  ).format(Decimal.parse('1234.56'));

  test('platform names parse to language and country', () {
    expect(DeviceRegion.parse('de_DE.UTF-8'), const Locale('de', 'DE'));
    expect(DeviceRegion.parse('de_DE@euro'), const Locale('de', 'DE'));
    expect(DeviceRegion.parse('en-GB'), const Locale('en', 'GB'));
    expect(DeviceRegion.parse('sr-Latn-RS'), const Locale('sr', 'RS'));
    expect(DeviceRegion.parse('C.UTF-8'), isNull);
    expect(DeviceRegion.parse('POSIX'), isNull);
    expect(DeviceRegion.parse(''), isNull);
  });

  test('English text in Germany writes German numbers in euros', () {
    DeviceRegion.locale = const Locale('en', 'DE');
    const Locale english = Locale('en');
    expect(DeviceRegion.currency(english), 'EUR');
    expect(money(english, 'EUR'), '1.234,56\u00a0€');
  });

  test('a language intl knows in that country keeps its own format', () {
    DeviceRegion.locale = const Locale('en', 'GB');
    expect(DeviceRegion.numberLocale(const Locale('en')), 'en_GB');
    expect(DeviceRegion.currency(const Locale('en')), 'GBP');
    DeviceRegion.locale = const Locale('en', 'US');
    expect(money(const Locale('en'), 'USD'), r'$1,234.56');
  });

  test('Russian text follows the region, not the language', () {
    DeviceRegion.locale = const Locale('de', 'DE');
    expect(DeviceRegion.currency(const Locale('ru')), 'EUR');
    expect(money(const Locale('ru'), 'EUR'), '1.234,56\u00a0€');
    DeviceRegion.locale = const Locale('en', 'RU');
    expect(DeviceRegion.currency(const Locale('en')), 'RUB');
    expect(money(const Locale('en'), 'RUB'), '1\u00a0234,56\u00a0₽');
  });

  test('without a region the app language decides', () {
    DeviceRegion.locale = null;
    expect(DeviceRegion.numberLocale(const Locale('ru')), 'ru');
    expect(DeviceRegion.currency(const Locale('ru')), 'RUB');
    expect(DeviceRegion.currency(const Locale('en')), 'USD');
  });

  test('a country intl has no language for falls back to the app language', () {
    DeviceRegion.locale = const Locale('en', 'BT');
    expect(DeviceRegion.numberLocale(const Locale('en')), 'en');
    expect(DeviceRegion.currency(const Locale('en')), 'INR');
  });
}
