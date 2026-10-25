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
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/core/ui/form_fields.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/period/freeze.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/dashboard/figure_info.dart';
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
  ScaffoldMessenger.of(context).say(message);
  return true;
}

/// State of the shown period: nothing while open, a warning before it
/// freezes, a notice once frozen.
class FreezeBanner extends ConsumerWidget {
  const FreezeBanner({required this.period, super.key});

  final BudgetPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final FreezeLookup lookup = ref.watch(freezeLookupProvider);
    final FreezeState state = lookup.stateOf(period);
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    final DateTime? until = period.unfrozenUntil;
    if (state == FreezeState.open &&
        until != null &&
        ref.watch(spaceClockProvider).nowUtc().isBefore(until)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: SageSpace.md),
        child: SageCard(
          color: sage.warningTint,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.lock_open_outlined, size: 18, color: sage.warning),
              const SizedBox(width: SageSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      tr(
                        'freeze.reopenedTitle',
                        args: <String>[
                          DateFormat.MMMMd(context.locale.toString())
                              .add_Hm()
                              .format(until.toLocal()),
                        ],
                      ),
                      style: text.labelLarge?.copyWith(color: sage.warning),
                    ),
                    if (period.unfreezeReason case final String reason)
                      Text(
                        tr('freeze.reopenedReason', args: <String>[reason]),
                        style: text.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (state == FreezeState.open) return const SizedBox.shrink();

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
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          frozen
                              ? tr('freeze.frozenTitle')
                              : tr('freeze.soonTitle'),
                          style: text.labelLarge?.copyWith(color: ink),
                        ),
                      ),
                      InfoButton(
                        FigureInfo(
                          title: tr('freeze.infoTitle'),
                          what: tr('freeze.infoWhat'),
                          note: tr('freeze.infoNote'),
                        ),
                        dense: true,
                      ),
                    ],
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
Future<String?> askUnfreezeReason(BuildContext context) => textDialog(
  context,
  title: tr('freeze.unfreezeTitle'),
  body: tr('freeze.unfreezeBody'),
  hint: tr('freeze.reasonHint'),
  confirmLabel: tr('freeze.unfreeze'),
  maxLength: TextLimits.reason,
  allowEmpty: false,
  capitalization: TextCapitalization.sentences,
);

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
