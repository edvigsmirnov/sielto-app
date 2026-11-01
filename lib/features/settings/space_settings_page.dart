import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/space_repository.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/choice_field.dart';
import 'package:sielto/core/ui/detail_host.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/core/ui/form_fields.dart';
import 'package:sielto/core/ui/layout.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/categories/categories_page.dart';
import 'package:sielto/features/incomes/income_rules_page.dart';
import 'package:sielto/features/members/members_data.dart';
import 'package:sielto/features/members/members_page.dart';
import 'package:sielto/features/security/security_page.dart';
import 'package:sielto/features/spaces/space_avatar.dart';
import 'package:sielto/features/sync/sync_controller.dart';

/// Settings for one Space, passed in so it can be any Space, not only the open
/// one.
class SpaceSettingsPage extends ConsumerStatefulWidget {
  const SpaceSettingsPage({required this.space, super.key});

  final Space space;

  @override
  ConsumerState<SpaceSettingsPage> createState() => _SpaceSettingsPageState();
}

class _SpaceSettingsPageState extends ConsumerState<SpaceSettingsPage> {
  late final TextEditingController _title = TextEditingController(
    text: widget.space.title,
  );

  /// True while the storage moves.
  bool _moving = false;

  /// The limit asks for the PIN once per visit, not on every step.
  bool _limitConfirmed = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  /// Amounts keep their numbers; only the sign changes.
  Future<void> _changeCurrency(Space space, String? code) async {
    if (code == null || code == space.currencyCode) return;
    final bool sure = await confirmDialog(
      context,
      title: tr('space.currencyChangeTitle', args: <String>[code]),
      body: tr('space.currencyChangeBody'),
      confirmLabel: tr('space.currencyChange'),
    );
    if (!mounted || !sure) return;
    await ref.read(repositoriesProvider).spaces.setCurrency(space.id, code);
  }

  @override
  Widget build(BuildContext context) {
    // Re-read so edits show immediately.
    final Space space =
        ref.watch(spaceByIdProvider(widget.space.id)) ?? widget.space;
    final bool isCurrent = ref.watch(currentSpaceProvider)?.id == space.id;
    final SpaceRepository repo = ref.watch(repositoriesProvider).spaces;
    final bool owner = space.ownerId == ref.watch(userIdProvider);
    final bool shared =
        space.storageMode == StorageMode.cloud && !space.isArchived;
    final int? memberCount = shared && owner
        ? ref.watch(membersProvider(space.id)).value?.count
        : null;

    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: sageAppBar(context, title: Text(tr('spaceSettings.title'))),
      body: ListView(
        padding: scrollPadding(
          context,
          const EdgeInsets.symmetric(
            horizontal: SageSpace.formGutter,
            vertical: SageSpace.md,
          ),
        ),
        children: <Widget>[
          Row(
            children: <Widget>[
              ExcludeSemantics(
                child: SpaceAvatar(
                  spaceId: space.id,
                  title: space.title,
                  size: 48,
                ),
              ),
              const SizedBox(width: SageSpace.md),
              Expanded(
                child: Semantics(
                  label: tr('space.fieldTitle'),
                  child: TextField(
                    controller: _title,
                    inputFormatters: titleLimit,
                    textCapitalization: TextCapitalization.sentences,
                    style: Theme.of(context).textTheme.bodyLarge,
                    onSubmitted: (String _) => _saveTitle(space),
                    onTapOutside: (PointerDownEvent _) => _saveTitle(space),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: SageSpace.lg),

          // Facts as label-value rows; only editable settings get controls.
          _FactRow(
            label: tr('space.fieldMode'),
            value: _LockedPill(text: tr('mode.${space.budgetMode.name}.name')),
          ),
          _Hint(tr('space.modeIsPermanent')),
          const SizedBox(height: SageSpace.lg),

          LabelledField(
            label: tr('space.fieldFeedOrder'),
            child: SegmentedChoice<FeedOrderMode>(
              values: FeedOrderMode.values,
              selected: space.feedOrderMode,
              labelOf: (FeedOrderMode mode) => tr('feedOrder.${mode.name}'),
              onChanged: (FeedOrderMode mode) =>
                  repo.setFeedOrderMode(space.id, mode),
            ),
          ),
          const SizedBox(height: SageSpace.xs),
          _Hint(
            '${tr('feedOrder.${space.feedOrderMode.name}Hint')} '
            '${tr('feedOrder.priorityHint')}',
          ),
          const SizedBox(height: SageSpace.lg),

          LabelledField(
            label: tr('space.fieldCurrency'),
            child: CurrencyField(
              value: space.currencyCode,
              onChanged: (String code) => _changeCurrency(space, code),
            ),
          ),
          const SizedBox(height: SageSpace.lg),

          _FactRow(
            label: tr('space.fieldTimezone'),
            value: Text(
              space.timezone,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const Hairline(),
          const SizedBox(height: SageSpace.lg),

          if (owner)
            LabelledField(
              label: tr('space.fieldStorage'),
              child: SegmentedChoice<StorageMode>(
                values: StorageMode.values,
                selected: space.storageMode,
                labelOf: (StorageMode m) => tr('storage.${m.name}.name'),
                enabled: !_moving,
                onChanged: (StorageMode m) => _changeStorage(space, m),
              ),
            )
          else
            _FactRow(
              label: tr('space.fieldStorage'),
              value: _LockedPill(
                text: tr('storage.${space.storageMode.name}.name'),
              ),
            ),
          const SizedBox(height: SageSpace.xs),
          _Hint(tr('storage.${space.storageMode.name}.body')),
          const SizedBox(height: SageSpace.lg),

          if (shared && owner) ...<Widget>[
            LabelledField(
              label: tr('members.limit'),
              child: _LimitStepper(
                limit: space.maxMembers,
                min: memberCount ?? 1,
                enabled: memberCount != null,
                onChanged: (int? n) => _setLimit(space, n, memberCount!),
              ),
            ),
            _Hint(
              tr(
                memberCount == null ? 'storage.noNetwork' : 'members.limitHint',
              ),
            ),
            const SizedBox(height: SageSpace.md),
          ],
          if (shared) ...<Widget>[
            LinkTile(
              padding: EdgeInsets.zero,
              title: tr('members.title'),
              onTap: () {
                ref.invalidate(membersProvider(space.id));
                unawaited(
                  pushPage<void>(context, MembersPage(spaceId: space.id)),
                );
              },
            ),
            const Hairline(),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('activity.toggle')),
              subtitle: Text(tr('activity.toggleHint')),
              value: !ref.watch(quietSpacesProvider).contains(space.id),
              onChanged: (bool on) => ref
                  .read(quietSpacesProvider.notifier)
                  .set(space.id, quiet: !on),
            ),
            const Hairline(),
          ],

          // Categories and income rules are for the open Space only.
          if (isCurrent) ...<Widget>[
            LinkTile(
              padding: EdgeInsets.zero,
              title: tr('category.title'),
              onTap: () => pushPage<void>(context, const CategoriesPage()),
            ),
            const Hairline(),
            LinkTile(
              padding: EdgeInsets.zero,
              title: tr('income.regularTitle'),
              onTap: () => pushPage<void>(context, const IncomeRulesPage()),
            ),
            const Hairline(),
          ],

          const SizedBox(height: SageSpace.xl),
          OutlinedButton(
            onPressed: () => _archive(space),
            child: Text(tr('space.archive')),
          ),
          const SizedBox(height: SageSpace.sm),
          _Hint(tr('space.archiveBody')),
          if (shared) ...<Widget>[
            const SizedBox(height: SageSpace.lg),
            DangerButton(
              label: tr('members.leave'),
              onPressed: () => owner ? _leaveAsOwner(space) : _leave(space),
            ),
          ],
          if (owner) ...<Widget>[
            const SizedBox(height: SageSpace.lg),
            DangerButton(
              label: tr('space.delete'),
              onPressed: () => _delete(space),
            ),
          ],
        ],
      ),
    );
  }

  /// An empty title reverts; an unchanged one writes nothing.
  Future<void> _saveTitle(Space space) async {
    final String title = _title.text.trim();
    if (title.isEmpty) {
      _title.text = space.title;
    } else if (title != space.title) {
      await ref.read(repositoriesProvider).spaces.setTitle(space.id, title);
    }
  }

  Future<void> _changeStorage(Space space, StorageMode mode) async {
    if (mode == space.storageMode) return;
    final String to = mode == StorageMode.cloud ? 'toCloud' : 'toLocal';
    final bool confirmed = await confirmDialog(
      context,
      title: tr('storage.${to}Title'),
      body: tr(
        'storage.${to}Body',
        namedArgs: <String, String>{'title': space.title},
      ),
      confirmLabel: tr('common.ok'),
    );
    if (!confirmed || !mounted) return;
    if (!await confirmIdentity(context, ref)) return;

    setState(() => _moving = true);
    final SyncController sync = ref.read(syncProvider.notifier);
    final CloudResult result = mode == StorageMode.cloud
        ? await sync.moveToCloud(space.id)
        : await sync.moveToLocal(space.id);
    if (!mounted) return;
    setState(() => _moving = false);
    _tellIfFailed(result);
  }

  void _tellIfFailed(CloudResult result) {
    if (result == CloudResult.done) return;
    ScaffoldMessenger.of(context).say(tr('storage.${result.name}'));
  }

  Future<void> _delete(Space space) async {
    final bool cloud = space.storageMode == StorageMode.cloud;
    final bool confirmed = await typedConfirmDialog(
      context,
      title: tr('space.deleteTitle'),
      body: tr(
        cloud ? 'space.deleteConfirmCloud' : 'space.deleteConfirm',
        namedArgs: <String, String>{'title': space.title},
      ),
      word: space.title,
      confirmLabel: tr('common.delete'),
    );
    if (!confirmed || !mounted) return;
    if (!await confirmIdentity(context, ref)) return;

    _done(
      await _closedWhile(space, () async {
        if (cloud) {
          return ref.read(syncProvider.notifier).deleteEverywhere(space.id);
        }
        await ref.read(repositoriesProvider).spaces.deleteForever(space.id);
        return CloudResult.done;
      }),
    );
  }

  /// Closes [space] while [action] runs; reopens it if [action] fails.
  Future<CloudResult> _closedWhile(
    Space space,
    Future<CloudResult> Function() action,
  ) async {
    final CurrentSpaceIdController current = ref.read(
      currentSpaceIdProvider.notifier,
    );
    final bool wasOpen = ref.read(currentSpaceIdProvider) == space.id;
    if (wasOpen) await current.select(null);
    final CloudResult result = await action();
    if (result != CloudResult.done && wasOpen) await current.select(space.id);
    return result;
  }

  /// Closes the page, or says why the action failed.
  void _done(CloudResult result) {
    if (!mounted) return;
    if (result == CloudResult.done) {
      Navigator.of(context).pop();
    } else {
      _tellIfFailed(result);
    }
  }

  Future<void> _setLimit(Space space, int? max, int members) async {
    if (!_limitConfirmed) {
      if (!await confirmIdentity(context, ref) || !mounted) return;
      _limitConfirmed = true;
    }
    if (max != null && max < members) {
      ScaffoldMessenger.of(context).say(tr('members.belowMembers'));
      return;
    }
    await ref.read(repositoriesProvider).spaces.setMaxMembers(space.id, max);
    unawaited(ref.read(syncProvider.notifier).syncNow());
  }

  Future<void> _leave(Space space) async {
    final bool confirmed = await confirmDialog(
      context,
      title: tr(
        'members.leaveTitle',
        namedArgs: <String, String>{'title': space.title},
      ),
      body: tr('members.leaveBody'),
      confirmLabel: tr('members.leave'),
      isDestructive: true,
    );
    if (confirmed) await _leaveNow(space);
  }

  /// The creator names a successor first; alone, leaving is deleting.
  Future<void> _leaveAsOwner(Space space) async {
    final SyncController sync = ref.read(syncProvider.notifier);
    final MemberList loaded = await ref.refresh(
      membersProvider(space.id).future,
    );
    if (!mounted) return;
    if (loaded.result != CloudResult.done) {
      _tellIfFailed(loaded.result);
      return;
    }
    final List<Member> others = <Member>[
      for (final Member m in loaded.members)
        if (!m.me) m,
    ];
    if (others.isEmpty) {
      await _delete(space);
      return;
    }
    final Member? successor = await choiceDialog<Member>(
      context,
      title: tr('members.pickOwnerTitle'),
      body: tr('members.pickOwnerBody'),
      columns: 1,
      choices: <(String, Member)>[
        for (final Member m in others) (loaded.nameOf(m), m),
      ],
    );
    if (successor == null || !mounted) return;
    if (!await confirmIdentity(context, ref)) return;
    if (!await sync.transferOwnership(space.id, successor.userId)) {
      if (mounted) _tellIfFailed(CloudResult.noNetwork);
      return;
    }
    await _leaveNow(space);
  }

  Future<void> _leaveNow(Space space) async => _done(
    await _closedWhile(
      space,
      () async => await ref.read(syncProvider.notifier).leaveSpace(space.id)
          ? CloudResult.done
          : CloudResult.noNetwork,
    ),
  );

  Future<void> _archive(Space space) async {
    final bool confirmed = await confirmDialog(
      context,
      title: tr('space.archiveTitle'),
      body: tr(
        'space.archiveConfirm',
        namedArgs: <String, String>{'title': space.title},
      ),
      confirmLabel: tr('space.archive'),
    );
    if (!confirmed) return;

    await ref
        .read(repositoriesProvider)
        .spaces
        .setArchived(space.id, isArchived: true);
    if (ref.read(currentSpaceIdProvider) == space.id) {
      await ref.read(currentSpaceIdProvider.notifier).select(null);
    }
    if (mounted) Navigator.of(context).pop();
  }
}

/// The member limit: minus, the number (tap to type), plus, and no limit.
class _LimitStepper extends StatelessWidget {
  const _LimitStepper({
    required this.limit,
    required this.min,
    required this.enabled,
    required this.onChanged,
  });

  /// Null means no limit.
  final int? limit;
  final int min;
  final bool enabled;
  final ValueChanged<int?> onChanged;

  Future<void> _type(BuildContext context, int value) async {
    final int? typed = int.tryParse(
      (await textDialog(
            context,
            title: tr('members.limit'),
            initial: '$value',
            keyboardType: TextInputType.number,
          )) ??
          '',
    );
    if (typed != null) onChanged(typed);
  }

  @override
  Widget build(BuildContext context) {
    final bool unlimited = limit == null;
    final int value = math.max(limit ?? min, min);
    final bool editable = enabled && !unlimited;
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            IconButton.outlined(
              tooltip: tr('members.fewer'),
              icon: const Icon(Icons.remove),
              onPressed: editable && value > min
                  ? () => onChanged(value - 1)
                  : null,
            ),
            Expanded(
              child: TextButton(
                onPressed: editable ? () => _type(context, value) : null,
                child: Text(
                  unlimited ? '∞' : '$value',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            IconButton.outlined(
              tooltip: tr('members.more'),
              icon: const Icon(Icons.add),
              onPressed: editable ? () => onChanged(value + 1) : null,
            ),
          ],
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('members.noLimit')),
          value: unlimited,
          onChanged: enabled ? (bool on) => onChanged(on ? null : value) : null,
        ),
      ],
    );
  }
}

/// Small print under a setting, in line with the row labels.
class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.bodySmall);
}

/// Read-only setting: label left, value right.
class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: SageSpace.md),
    child: Row(
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(width: SageSpace.md),
        Expanded(
          child: Align(alignment: AlignmentDirectional.centerEnd, child: value),
        ),
      ],
    ),
  );
}

/// A value that cannot change.
class _LockedPill extends StatelessWidget {
  const _LockedPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: sage.canvas,
        borderRadius: BorderRadius.circular(SageRadius.pill),
        border: Border.all(color: sage.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.lock_outline, size: 13, color: sage.inkLabel),
          const SizedBox(width: SageSpace.xs),
          Flexible(
            child: Text(
              text,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: sage.inkSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
