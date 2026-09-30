import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/feed/feed_menu.dart';

/// Long-press on a calendar day: the + button's actions on that day.
Future<void> showDayMenu(
  BuildContext context,
  WidgetRef ref, {
  required CalendarDate date,
}) => showQuickAddMenu(
  context,
  ref,
  date: date,
  title: DateLabels(context.locale.toString()).weekdayAndDate(date),
  askDate: false,
);
