import 'package:drift/drift.dart' show Value;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/deadline_guard.dart';
import 'package:sielto/core/db/freeze_guard.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/feed/feed_menu.dart';
import 'package:sielto/features/feed/feed_model.dart';
import 'package:sielto/features/payments/category_picker.dart';
import 'package:sielto/features/periods/freeze_providers.dart';

/// Selected Feed record ids. Cleared when the Space changes.
class FeedSelectionController extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.watch(currentSpaceIdProvider);
    return const <String>{};
  }

  void toggle(String id) => state = state.contains(id)
      ? (Set<String>.of(state)..remove(id))
      : <String>{...state, id};

  void clear() => state = const <String>{};
}

final NotifierProvider<FeedSelectionController, Set<String>>
feedSelectionProvider = NotifierProvider<FeedSelectionController, Set<String>>(
  FeedSelectionController.new,
);

enum _Bulk { done, notDone, category, delete }

/// Actions over [records]; one record also gets the long-press menu items.
Future<void> showBulkActions(
  BuildContext context,
  WidgetRef ref, {
  required List<FeedRecord> records,
}) async {
  if (records.isEmpty) return;
  final bool anyPayment = records.any((FeedRecord r) => !r.isIncome);
  final _Bulk? choice = await showModalBottomSheet<_Bulk>(
    context: context,
    builder: (BuildContext sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            title: Text(
              tr(
                'feed.bulk.selected',
                namedArgs: <String, String>{'count': '${records.length}'},
              ),
              style: Theme.of(sheet).textTheme.titleSmall,
            ),
          ),
          if (records.length == 1)
            ...recordMenuTiles(context, ref, records.single, sheet),
          if (records.any((FeedRecord r) => !r.isPaid))
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text(tr('feed.bulk.done')),
              onTap: () => Navigator.of(sheet).pop(_Bulk.done),
            ),
          if (records.any((FeedRecord r) => r.isPaid))
            ListTile(
              leading: const Icon(Icons.radio_button_unchecked),
              title: Text(tr('feed.bulk.notDone')),
              onTap: () => Navigator.of(sheet).pop(_Bulk.notDone),
            ),
          if (anyPayment)
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: Text(tr('feed.bulk.category')),
              onTap: () => Navigator.of(sheet).pop(_Bulk.category),
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(tr('common.delete')),
            onTap: () => Navigator.of(sheet).pop(_Bulk.delete),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  final Future<bool> action = switch (choice) {
    _Bulk.done => _setDone(context, ref, records, done: true),
    _Bulk.notDone => _setDone(context, ref, records, done: false),
    _Bulk.category => _setCategory(context, ref, records),
    _Bulk.delete => _delete(context, ref, records),
  };
  if (await action) ref.read(feedSelectionProvider.notifier).clear();
}

/// Runs [write] per record; frozen or refused ones are counted as skipped.
Future<List<FeedRecord>> _each(
  WidgetRef ref,
  List<FeedRecord> records,
  Future<void> Function(FeedRecord r) write, {
  bool frozenAllowed = false,
}) async {
  final FreezeLookup freeze = ref.read(freezeLookupProvider);
  final List<FeedRecord> written = <FeedRecord>[];
  for (final FeedRecord r in records) {
    if (!frozenAllowed && freeze.isFrozen(r.budgetPeriodId)) continue;
    try {
      await write(r);
      written.add(r);
    } on PeriodFrozen {
      continue;
    } on BeyondHardDeadline {
      continue;
    }
  }
  return written;
}

void _saySkipped(BuildContext context, int skipped) {
  if (skipped == 0 || !context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          tr(
            'feed.bulk.skipped',
            namedArgs: <String, String>{'count': '$skipped'},
          ),
        ),
      ),
    );
}

/// An income without an amount is left alone: a receipt needs one.
Future<bool> _setDone(
  BuildContext context,
  WidgetRef ref,
  List<FeedRecord> records, {
  required bool done,
}) async {
  final List<FeedRecord> targets = <FeedRecord>[
    for (final FeedRecord r in records)
      if (r.isPaid != done && !(done && r.isIncome && r.amount == null)) r,
  ];
  if (!done &&
      targets.any((FeedRecord r) => r.isMandatory) &&
      !await confirmMandatory(context, MandatoryChange.unpay)) {
    return false;
  }
  final Repositories repos = ref.read(repositoriesProvider);
  final List<FeedRecord> written = await _each(ref, targets, (FeedRecord r) {
    if (!r.isIncome) return repos.payments.setPaid(r.id, isPaid: done);
    return done
        ? repos.incomes.markReceived(r.id)
        : repos.incomes.update(
            r.id,
            isPaid: const Value<bool>(false),
            actualDate: const Value<CalendarDate?>(null),
          );
  });
  ref.invalidate(periodRefreshProvider);
  if (context.mounted) _saySkipped(context, targets.length - written.length);
  return true;
}

/// Incomes have no category.
Future<bool> _setCategory(
  BuildContext context,
  WidgetRef ref,
  List<FeedRecord> records,
) async {
  final CategoryChoice? choice = await pickCategory(context, selectedId: null);
  if (choice == null) return false;
  final Repositories repos = ref.read(repositoriesProvider);
  await _each(
    ref,
    <FeedRecord>[
      for (final FeedRecord r in records)
        if (!r.isIncome) r,
    ],
    (FeedRecord r) => repos.payments.update(
      r.id,
      categoryId: Value<String?>(choice.category?.id),
    ),
    frozenAllowed: true,
  );
  return true;
}

Future<bool> _delete(
  BuildContext context,
  WidgetRef ref,
  List<FeedRecord> records,
) async {
  if (records.any((FeedRecord r) => r.isMandatory) &&
      !await confirmMandatory(context, MandatoryChange.delete)) {
    return false;
  }
  final Repositories repos = ref.read(repositoriesProvider);
  final List<FeedRecord> deleted = await _each(
    ref,
    records,
    (FeedRecord r) => r.isIncome
        ? repos.incomes.softDelete(r.id)
        : repos.payments.softDelete(r.id),
  );
  ref.invalidate(periodRefreshProvider);
  if (!context.mounted) return true;
  final int skipped = records.length - deleted.length;
  if (deleted.isEmpty) {
    _saySkipped(context, skipped);
    return true;
  }
  showUndoSnackbar(
    context,
    message: <String>[
      tr(
        'feed.bulk.deleted',
        namedArgs: <String, String>{'count': '${deleted.length}'},
      ),
      if (skipped > 0)
        tr(
          'feed.bulk.skipped',
          namedArgs: <String, String>{'count': '$skipped'},
        ),
    ].join(' · '),
    onUndo: () async {
      for (final FeedRecord r in deleted) {
        await (r.isIncome
            ? repos.incomes.restore(r.id)
            : repos.payments.restore(r.id));
      }
      ref.invalidate(periodRefreshProvider);
    },
  );
  return true;
}
