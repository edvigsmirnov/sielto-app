import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/deadline_guard.dart';
import 'package:sielto/core/db/freeze_guard.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/period/freeze.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/periods/freeze_providers.dart';

/// Runs [write] and reports a freeze or deadline refusal as a message.
Future<bool> guardWrite(
  BuildContext context,
  Future<void> Function() write,
) async {
  try {
    await write();
    return true;
  } on Exception catch (e) {
    if (e is! PeriodFrozen && e is! BeyondHardDeadline) rethrow;
    if (context.mounted) sayRefusal(context, e);
    return false;
  }
}

/// Explains a freeze or deadline refusal. False for any other error.
bool sayRefusal(BuildContext context, Exception error) {
  final String? message = switch (error) {
    PeriodFrozen() => tr('freeze.refused'),
    BeyondHardDeadline(:final CalendarDate deadline) => tr(
      'budget.refusedBeyondDeadline',
      namedArgs: <String, String>{
        'date': DateLabels(context.locale.toString()).dayMonth(deadline),
      },
    ),
    _ => null,
  };
  if (message == null) return false;
  _say(context, message);
  return true;
}

void _say(BuildContext context, String message) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message)));

/// State of the shown period: nothing while open, a warning before it
/// freezes, a notice once frozen.
class FreezeBanner extends ConsumerWidget {
  const FreezeBanner({required this.period, super.key});

  final BudgetPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final FreezeLookup lookup = ref.watch(freezeLookupProvider);
    final FreezeState state = lookup.stateOf(period);
    if (state == FreezeState.open) return const SizedBox.shrink();

    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    final bool frozen = state == FreezeState.frozen;
    final Color ink = frozen ? sage.inkSecondary : sage.warning;

    // Only the Space creator may reopen a frozen period.
    final Space? space = ref.watch(currentSpaceProvider);
    final bool isOwner =
        space != null && space.ownerId == ref.watch(userIdProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: SageSpace.md),
      child: SageCard(
        color: frozen ? sage.card : sage.warningTint,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              frozen ? Icons.lock_outline : Icons.schedule,
              size: 18,
              color: ink,
            ),
            const SizedBox(width: SageSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    frozen ? tr('freeze.frozenTitle') : tr('freeze.soonTitle'),
                    style: text.labelLarge?.copyWith(color: ink),
                  ),
                  const SizedBox(height: SageSpace.xs),
                  Text(
                    frozen
                        ? tr('freeze.frozenBody')
                        : plural(
                            'freeze.soonBody',
                            lookup.daysUntilFreeze(period),
                          ),
                    style: text.bodySmall,
                  ),
                  if (frozen && isOwner) ...<Widget>[
                    const SizedBox(height: SageSpace.xs),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: () => _unfreeze(context, ref),
                        child: Text(tr('freeze.unfreeze')),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _unfreeze(BuildContext context, WidgetRef ref) async {
    final String? reason = await askUnfreezeReason(context);
    if (reason == null) return;

    final Repositories repos = ref.read(repositoriesProvider);
    const FreezeEvaluator evaluator = FreezeEvaluator();
    await repos.periods.unfreeze(
      period.id,
      evaluator.unfreezeExpiry(ref.read(spaceClockProvider).nowUtc()),
      reason,
    );
  }
}

/// Null when dismissed.
Future<String?> askUnfreezeReason(BuildContext context) => showDialog<String>(
  context: context,
  builder: (BuildContext context) => const _UnfreezeDialog(),
);

/// Owns its controller: the dialog outlives the future during its exit.
class _UnfreezeDialog extends StatefulWidget {
  const _UnfreezeDialog();

  @override
  State<_UnfreezeDialog> createState() => _UnfreezeDialogState();
}

class _UnfreezeDialogState extends State<_UnfreezeDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final String reason = _controller.text.trim();

    return AlertDialog(
      backgroundColor: sage.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SageRadius.card),
      ),
      title: Text(
        tr('freeze.unfreezeTitle'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            tr('freeze.unfreezeBody'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: SageSpace.md),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: tr('freeze.reasonHint')),
            onChanged: (String _) => setState(() {}),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('common.cancel')),
        ),
        TextButton(
          // A reason is required.
          onPressed: reason.isEmpty
              ? null
              : () => Navigator.of(context).pop(reason),
          child: Text(tr('freeze.unfreeze')),
        ),
      ],
    );
  }
}

/// Shown in place of protected fields.
class FreezeNotice extends StatelessWidget {
  const FreezeNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return Padding(
      padding: const EdgeInsets.only(bottom: SageSpace.md),
      child: SageCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.lock_outline, size: 18, color: sage.inkLabel),
            const SizedBox(width: SageSpace.sm),
            Expanded(
              child: Text(
                tr('freeze.formNotice'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
