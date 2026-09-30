import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/space_repository.dart';
import 'package:sielto/core/format/currencies.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/categories/categories_page.dart';
import 'package:sielto/features/incomes/income_rules_page.dart';
import 'package:sielto/features/spaces/space_avatar.dart';

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

  /// Null while the check runs.
  bool? _currencyEditable;

  @override
  void initState() {
    super.initState();
    _checkCurrency();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _checkCurrency() async {
    final bool editable = await ref
        .read(repositoriesProvider)
        .spaces
        .canChangeCurrency(widget.space.id);
    if (mounted) setState(() => _currencyEditable = editable);
  }

  @override
  Widget build(BuildContext context) {
    // Re-read so edits show immediately.
    final Space space =
        ref
            .watch(spaceListProvider)
            .value
            ?.where((Space s) => s.id == widget.space.id)
            .firstOrNull ??
        widget.space;
    final bool isCurrent = ref.watch(currentSpaceProvider)?.id == space.id;
    final SpaceRepository repo = ref.watch(repositoriesProvider).spaces;
    final String locale = context.locale.toString();

    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: AppBar(title: Text(tr('spaceSettings.title'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: SageSpace.formGutter,
          vertical: SageSpace.md,
        ),
        children: <Widget>[
          Row(
            children: <Widget>[
              SpaceAvatar(spaceId: space.id, title: space.title, size: 48),
              const SizedBox(width: SageSpace.md),
              Expanded(
                child: TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  style: Theme.of(context).textTheme.bodyLarge,
                  onSubmitted: (String _) => _saveTitle(space),
                  onTapOutside: (PointerDownEvent _) => _saveTitle(space),
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
          Text(
            tr('space.modeIsPermanent'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
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
          const SizedBox(height: SageSpace.lg),

          if (_currencyEditable ?? false)
            LabelledField(
              label: tr('space.fieldCurrency'),
              child: DropdownButtonFormField<String>(
                initialValue: space.currencyCode,
                items: <DropdownMenuItem<String>>[
                  for (final String code in Currencies.offered(
                    space.currencyCode,
                  ))
                    DropdownMenuItem<String>(
                      value: code,
                      child: Text(Currencies.label(code, locale)),
                    ),
                ],
                onChanged: (String? code) async {
                  if (code == null) return;
                  await repo.setCurrency(space.id, code);
                },
              ),
            )
          else
            // Frozen by the first record.
            _FactRow(
              label: tr('space.fieldCurrency'),
              value: _LockedPill(text: space.currencyCode),
            ),
          const Hairline(),

          _FactRow(
            label: tr('space.fieldTimezone'),
            value: Text(
              space.timezone,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const Hairline(),

          // Categories and income rules are for the open Space only.
          if (isCurrent) ...<Widget>[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('category.title')),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext _) => const CategoriesPage(),
                ),
              ),
            ),
            const Hairline(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('income.regularTitle')),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext _) => const IncomeRulesPage(),
                ),
              ),
            ),
            const Hairline(),
          ],

          const SizedBox(height: SageSpace.xl),
          OutlinedButton(
            onPressed: () => _archive(space),
            child: Text(tr('space.archive')),
          ),
          const SizedBox(height: SageSpace.sm),
          Text(
            tr('space.archiveBody'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (space.ownerId == ref.watch(userIdProvider)) ...<Widget>[
            const SizedBox(height: SageSpace.lg),
            _DangerButton(
              label: tr('space.delete'),
              onTap: () => _delete(space),
            ),
          ],
        ],
      ),
    );
  }

  /// Archiving is local.
  /// An empty title reverts; an unchanged one writes nothing.
  Future<void> _saveTitle(Space space) async {
    final String title = _title.text.trim();
    if (title.isEmpty) {
      _title.text = space.title;
    } else if (title != space.title) {
      await ref.read(repositoriesProvider).spaces.setTitle(space.id, title);
    }
  }

  Future<void> _delete(Space space) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext _) => _DeleteDialog(title: space.title),
    );
    if (confirmed != true) return;

    if (ref.read(currentSpaceIdProvider) == space.id) {
      await ref.read(currentSpaceIdProvider.notifier).select(null);
    }
    await ref.read(repositoriesProvider).spaces.deleteForever(space.id);
    if (mounted) Navigator.of(context).pop();
  }

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

/// Asks for the Space name before a delete.
class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({required this.title});

  final String title;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  final TextEditingController _typed = TextEditingController();

  @override
  void initState() {
    super.initState();
    _typed.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final bool matches = _typed.text.trim() == widget.title.trim();
    return AlertDialog(
      backgroundColor: sage.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SageRadius.card),
      ),
      title: Text(
        tr('space.deleteTitle'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            tr(
              'space.deleteConfirm',
              namedArgs: <String, String>{'title': widget.title},
            ),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: SageSpace.md),
          TextField(
            controller: _typed,
            autofocus: true,
            decoration: InputDecoration(hintText: widget.title),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(tr('common.cancel')),
        ),
        TextButton(
          onPressed: matches ? () => Navigator.of(context).pop(true) : null,
          style: TextButton.styleFrom(foregroundColor: sage.danger),
          child: Text(tr('common.delete')),
        ),
      ],
    );
  }
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
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
        ),
        const SizedBox(width: SageSpace.md),
        value,
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
          Text(
            text,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: sage.inkSecondary),
          ),
        ],
      ),
    );
  }
}

/// Destructive action on a tinted button.
class _DangerButton extends StatelessWidget {
  const _DangerButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SageRadius.button),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sage.dangerTint,
          borderRadius: BorderRadius.circular(SageRadius.button),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: sage.danger),
        ),
      ),
    );
  }
}
