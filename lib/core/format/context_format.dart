import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';

/// Formatters in the reader's language.
extension ContextFormat on BuildContext {
  DateLabels get dates => DateLabels(locale.toString());

  MoneyFormat moneyIn(String currencyCode) =>
      MoneyFormat(locale: locale.toString(), currencyCode: currencyCode);
}
