import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/sync/sync_worker.dart';
import 'package:sielto/domain/value/calendar_date.dart';

/// A change by another member; [who] is the name this user sees.
typedef Activity = ({RemoteChange change, String? who});

class ActivityController extends Notifier<List<Activity>> {
  @override
  List<Activity> build() => const <Activity>[];

  void post(List<Activity> batch) => state = batch;
}

/// What other members changed in the last sync.
final NotifierProvider<ActivityController, List<Activity>> activityProvider =
    NotifierProvider<ActivityController, List<Activity>>(
      ActivityController.new,
    );

typedef RemoteEdit = ({String spaceId, DateTime at});

class RemoteEditController extends Notifier<RemoteEdit?> {
  @override
  RemoteEdit? build() => null;

  void mark(String spaceId) => state = (spaceId: spaceId, at: DateTime.now());
}

/// When another member's change last reached a Space here.
final NotifierProvider<RemoteEditController, RemoteEdit?> remoteEditProvider =
    NotifierProvider<RemoteEditController, RemoteEdit?>(
      RemoteEditController.new,
    );

/// Conflicts always show. Other changes show for the open Space unless it is
/// quiet, one by one or as a count.
void showActivity(
  BuildContext context,
  WidgetRef ref,
  List<Activity> batch, {
  required void Function(CalendarDate day) onShow,
}) {
  final String locale = context.locale.toString();
  final String? open = ref.read(currentSpaceIdProvider);
  final Set<String> quiet = ref.read(quietSpacesProvider);
  final List<Space> spaces = ref.read(spaceListProvider).value ?? <Space>[];
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  String nameOf(Activity a) => a.who ?? tr('members.noName');

  void toast(String message, CalendarDate? day) => messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 5),
      persist: false,
      action: day == null
          ? null
          : SnackBarAction(
              label: tr('activity.show'),
              onPressed: () => onShow(day),
            ),
    ),
  );

  for (final Activity a in batch) {
    final RemoteChange c = a.change;
    final ConflictKind? conflict = c.conflict;
    if (conflict == null) continue;
    toast(
      tr(
        'activity.${conflict.name}',
        namedArgs: <String, String>{
          'title': c.title,
          'who': nameOf(a),
          'theirs': _time(c.theirs, locale),
          'mine': c.mine == null ? '' : _time(c.mine!, locale),
        },
      ),
      c.spaceId == open ? c.date : null,
    );
  }

  final List<Activity> news = <Activity>[
    for (final Activity a in batch)
      if (a.change.conflict == null &&
          a.change.spaceId == open &&
          !quiet.contains(open))
        a,
  ];
  if (news.isEmpty) return;
  if (news.length > 1) {
    toast(
      plural(
        'activity.many',
        news.length,
        namedArgs: <String, String>{
          'who': <String>{for (final Activity a in news) nameOf(a)}.join(', '),
        },
      ),
      null,
    );
    return;
  }

  final RemoteChange c = news.single.change;
  final Space? space = spaces.where((Space s) => s.id == c.spaceId).firstOrNull;
  final String what = <String>[
    c.title,
    if ((c.amount, space) case (final amount?, final Space s))
      MoneyFormat(locale: locale, currencyCode: s.currencyCode).format(amount),
    DateLabels(locale).dayMonth(c.date),
  ].join(', ');
  toast(
    tr(
      'activity.${c.kind.name}${c.income ? 'Income' : 'Payment'}',
      namedArgs: <String, String>{'who': nameOf(news.single), 'what': what},
    ),
    c.date,
  );
}

/// The time alone for today, with the day otherwise.
String _time(DateTime at, String locale) {
  final DateTime local = at.toLocal();
  final DateTime now = DateTime.now();
  final bool today =
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  return (today ? DateFormat.Hm(locale) : DateFormat.MMMd(locale).add_Hm())
      .format(local);
}
