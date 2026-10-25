import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/format/context_format.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/features/feed/feed_model.dart';
import 'package:sielto/features/sync/sync_controller.dart';

enum _Resolution { note, shared }

/// On an entry whose edit the server refused in a closed period. Tapping it
/// keeps the edit as a note or takes the shared version back.
class RefusedMark extends ConsumerWidget {
  const RefusedMark(this.record, {super.key});

  final FeedRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    tooltip: tr('refused.tooltip'),
    icon: Icon(Icons.sync_problem, size: 18, color: context.sage.warningAccent),
    onPressed: () => _resolve(context, ref),
  );

  Future<void> _resolve(BuildContext context, WidgetRef ref) async {
    final _Resolution? choice = await choiceDialog<_Resolution>(
      context,
      title: tr('refused.title'),
      body: tr('refused.body'),
      columns: 1,
      choices: <(String, _Resolution)>[
        (tr('refused.keepNote'), _Resolution.note),
        (tr('refused.takeShared'), _Resolution.shared),
      ],
    );
    if (choice == null || !context.mounted) return;
    final Space? space = ref.read(currentSpaceProvider);
    final String note = tr(
      'refused.noteText',
      namedArgs: <String, String>{
        'what': <String>[
          record.title,
          if ((record.amount, space) case (final amount?, final Space s))
            context.moneyIn(s.currencyCode).format(amount),
          context.dates.dayMonth(record.date),
        ].join(', '),
      },
    );
    final bool done = await ref
        .read(syncProvider.notifier)
        .resolveRefused(
          record.isIncome ? 'incomes' : 'payments',
          record.id,
          note: choice == _Resolution.note ? note : null,
          on: ref.read(spaceClockProvider).today(),
        );
    if (!done && context.mounted) {
      ScaffoldMessenger.of(context).say(tr('storage.noNetwork'));
    }
  }
}
