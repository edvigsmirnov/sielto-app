import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/time/space_clock.dart';
import 'package:sielto/core/ui/choice_field.dart';
import 'package:sielto/core/ui/detail_host.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/core/ui/form_fields.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/members/join_space_page.dart';
import 'package:sielto/features/onboarding/onboarding_scaffold.dart';
import 'package:sielto/features/spaces/starter_categories.dart';
import 'package:sielto/features/sync/sync_controller.dart';

/// In the order shown on the form.
const List<BudgetMode> offeredBudgetModes = <BudgetMode>[
  BudgetMode.incomeDriven,
  BudgetMode.flow,
  BudgetMode.budget,
];

/// Creates a Space. The budget mode is permanent.
class SpaceFormPage extends ConsumerStatefulWidget {
  const SpaceFormPage({
    this.isFirstSpace = false,
    this.step,
    this.stepCount,
    super.key,
  });

  /// Onboarding: no app bar.
  final bool isFirstSpace;

  /// Onboarding step number. Null outside onboarding.
  final int? step;
  final int? stepCount;

  @override
  ConsumerState<SpaceFormPage> createState() => _SpaceFormPageState();
}

class _SpaceFormPageState extends ConsumerState<SpaceFormPage> {
  final TextEditingController _title = TextEditingController();
  BudgetMode _mode = BudgetMode.flow;
  StorageMode _storage = StorageMode.local;
  String? _currency;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  bool get _canSave => _title.text.trim().isNotEmpty && !_saving;

  Future<void> _create(String currency) async {
    setState(() => _saving = true);
    // A first Space replaces onboarding with the shell mid-way.
    final SyncController sync = ref.read(syncProvider.notifier);
    final CurrentSpaceIdController current = ref.read(
      currentSpaceIdProvider.notifier,
    );
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final Space space = await ref
          .read(repositoriesProvider)
          .createSpace(
            title: _title.text,
            budgetMode: _mode,
            ownerId: ref.read(userIdProvider),
            timezone: await _deviceTimezone(),
            currencyCode: currency,
            starters: starterCategories(),
          );
      if (_storage == StorageMode.cloud) {
        final CloudResult result = await sync.moveToCloud(space.id);
        if (result != CloudResult.done) {
          messenger.say(tr('storage.${result.name}'));
        }
      }
      await current.select(space.id);
      // Pops to the shell.
      if (mounted && !widget.isFirstSpace) {
        Navigator.of(context).popUntil((Route<void> r) => r.isFirst);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// From the device; UTC when the platform name is unknown.
  Future<String> _deviceTimezone() async {
    try {
      final String name = (await FlutterTimezone.getLocalTimezone()).identifier;
      return SpaceClock.isKnownTimezone(name) ? name : 'UTC';
    } on Exception {
      return 'UTC';
    }
  }

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    // Onboarding answer, else the device locale.
    final String currency =
        _currency ??
        ref.read(localSettingsProvider).currencyFor(context.locale.toString());
    final VoidCallback? create = _canSave ? () => _create(currency) : null;

    final int? step = widget.step;
    final int? stepCount = widget.stepCount;

    // Onboarding frame: progress bar and pinned primary action.
    if (step != null && stepCount != null) {
      return Scaffold(
        backgroundColor: sage.surface,
        body: OnboardingScaffold(
          step: step,
          stepCount: stepCount,
          title: tr('space.firstTitle'),
          body: tr('space.firstBody'),
          primaryLabel: tr('space.create'),
          onPrimary: create,
          secondaryLabel: tr('members.joinWithCode'),
          onSecondary: () => pushPage<void>(context, const JoinSpacePage()),
          // Currency was asked in the previous step.
          children: _fields(currency, showCurrency: false),
        ),
      );
    }

    return Scaffold(
      backgroundColor: sage.surface,
      appBar: sageAppBar(context, title: Text(tr('space.createTitle'))),
      bottomNavigationBar: FormActionBar(
        child: FilledButton(onPressed: create, child: Text(tr('space.create'))),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SageSpace.formGutter),
          children: _fields(currency, showCurrency: true),
        ),
      ),
    );
  }

  /// Form body, shared by the onboarding frame and the standalone screen.
  List<Widget> _fields(String currency, {required bool showCurrency}) =>
      <Widget>[
        LabelledField(
          label: tr('space.fieldTitle'),
          child: TextField(
            controller: _title,
            inputFormatters: titleLimit,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: tr('space.titleHint')),
          ),
        ),
        const SizedBox(height: SageSpace.lg),
        FieldLabel(tr('space.fieldMode')),
        for (final BudgetMode mode in offeredBudgetModes) ...<Widget>[
          _RadioCard(
            title: tr('mode.${mode.name}.name'),
            body: tr('mode.${mode.name}.body'),
            note: tr('mode.${mode.name}.examples'),
            selected: _mode == mode,
            onTap: () => setState(() => _mode = mode),
          ),
          const SizedBox(height: SageSpace.sm),
        ],
        Text(
          tr('space.modeIsPermanent'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (showCurrency) ...<Widget>[
          const SizedBox(height: SageSpace.lg),
          LabelledField(
            label: tr('space.fieldCurrency'),
            child: CurrencyField(
              value: currency,
              onChanged: (String code) => setState(() => _currency = code),
            ),
          ),
        ],
        const SizedBox(height: SageSpace.lg),
        FieldLabel(tr('space.fieldStorage')),
        for (final StorageMode mode in StorageMode.values) ...<Widget>[
          if (mode != StorageMode.values.first)
            const SizedBox(height: SageSpace.sm),
          _RadioCard(
            title: tr('storage.${mode.name}.name'),
            body: tr('storage.${mode.name}.body'),
            selected: _storage == mode,
            onTap: () => setState(() => _storage = mode),
          ),
        ],
      ];
}

/// One choice of several, with its description and an optional note.
class _RadioCard extends StatelessWidget {
  const _RadioCard({
    required this.title,
    required this.body,
    required this.selected,
    required this.onTap,
    this.note,
  });

  final String title;
  final String body;
  final String? note;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SageCard(
      selected: selected,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 20,
            color: selected ? context.sage.accentStrong : context.sage.inkLabel,
          ),
          const SizedBox(width: SageSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: text.titleSmall),
                const SizedBox(height: SageSpace.xs),
                Text(body, style: text.bodyMedium),
                if (note != null) ...<Widget>[
                  const SizedBox(height: SageSpace.xs),
                  Text(note!, style: text.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
