import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/domain/value/calendar_date.dart';

/// Formatters in the reader's language.
extension ContextFormat on BuildContext {
  DateLabels get dates => DateLabels(locale.toString());

  MoneyFormat moneyIn(String currencyCode) =>
      MoneyFormat(locale: locale.toString(), currencyCode: currencyCode);

  /// "Title, amount, day" for a message about an entry; no amount without
  /// [currencyCode].
  String entryLine(
    String title,
    Decimal? amount,
    CalendarDate date, {
    String? currencyCode,
  }) => <String>[
    title,
    if ((amount, currencyCode) case (final Decimal a?, final String c?))
      moneyIn(c).format(a),
    dates.dayMonth(date),
  ].join(', ');
}
