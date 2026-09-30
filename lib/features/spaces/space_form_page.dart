import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/format/currencies.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/time/space_clock.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/onboarding/onboarding_scaffold.dart';
import 'package:sielto/features/spaces/starter_categories.dart';

/// In the order shown on the form.
const List<BudgetMode> offeredBudgetModes = <BudgetMode>[
  BudgetMode.incomeDriven,
  BudgetMode.flow,
  BudgetMode.budget,
];

/// Creates a Space. The budget mode is permanent; the currency freezes at the
/// first record.
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

  Future<void> _create() async {
    setState(() => _saving = true);
    final Repositories repos = ref.read(repositoriesProvider);
    final String locale = context.locale.toString();
    // Onboarding answer, else the device locale.
    final String currency =
        _currency ??
        ref.read(localSettingsProvider).currencyCode ??
        Currencies.forLocale(locale);

    try {
      final String timezone = await _deviceTimezone();
      final Space space = await repos.db.transaction(() async {
        final Space space = await repos.spaces.create(
          title: _title.text,
          spaceType: SpaceType.personal,
          budgetMode: _mode,
          ownerId: ref.read(userIdProvider),
          timezone: timezone,
          currencyCode: currency,
        );
        await repos.categories.createStarterSet(space.id, <
          ({
            String key,
            String title,
            String? icon,
            String? color,
            ExpenseType type,
          })
        >[
          for (final StarterCategory c in starterCategories())
            (
              key: c.key,
              title: c.title,
              icon: c.icon,
              color: c.color,
              type: c.expenseType,
            ),
        ]);
        // Flow and Budget hold exactly one continuous period.
        if (_mode != BudgetMode.incomeDriven) {
          await repos.periods.ensureContinuous(
            spaceId: space.id,
            startDate: repos.spaces.clockFor(space).today(),
          );
        }
        return space;
      });
      await ref.read(currentSpaceIdProvider.notifier).select(space.id);
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
    final String locale = context.locale.toString();
    // Onboarding answer, else the device locale.
    final String currency =
        _currency ??
        ref.read(localSettingsProvider).currencyCode ??
        Currencies.forLocale(locale);

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
          onPrimary: _canSave ? _create : null,
          // Currency was asked in the previous step.
          children: _fields(locale, currency, showCurrency: false),
        ),
      );
    }

    return Scaffold(
      backgroundColor: sage.surface,
      appBar: AppBar(title: Text(tr('space.createTitle'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SageSpace.formGutter),
          children: <Widget>[
            ..._fields(locale, currency, showCurrency: true),
            const SizedBox(height: SageSpace.xl),
            FilledButton(
              onPressed: _canSave ? _create : null,
              child: Text(tr('space.create')),
            ),
          ],
        ),
      ),
    );
  }

  /// Form body, shared by the onboarding frame and the standalone screen.
  List<Widget> _fields(
    String locale,
    String currency, {
    required bool showCurrency,
  }) => <Widget>[
    LabelledField(
      label: tr('space.fieldTitle'),
      child: TextField(
        controller: _title,
        textInputAction: TextInputAction.next,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: tr('space.titleHint')),
      ),
    ),
    const SizedBox(height: SageSpace.lg),
    FieldLabel(tr('space.fieldMode')),
    for (final BudgetMode mode in offeredBudgetModes) ...<Widget>[
      _ModeCard(
        mode: mode,
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
        child: DropdownButtonFormField<String>(
          initialValue: currency,
          items: <DropdownMenuItem<String>>[
            for (final String code in Currencies.offered(currency))
              DropdownMenuItem<String>(
                value: code,
                child: Text(Currencies.label(code, locale)),
              ),
          ],
          onChanged: (String? code) =>
              setState(() => _currency = code ?? currency),
        ),
      ),
      const SizedBox(height: SageSpace.xs),
      Text(
        tr('space.currencyFreezes'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
    const SizedBox(height: SageSpace.lg),
    FieldLabel(tr('space.fieldStorage')),
    const _StorageChoice(),
  ];
}

/// A mode with its description and examples.
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final BudgetMode mode;
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
                Text(tr('mode.${mode.name}.name'), style: text.titleSmall),
                const SizedBox(height: SageSpace.xs),
                Text(tr('mode.${mode.name}.body'), style: text.bodyMedium),
                const SizedBox(height: SageSpace.xs),
                Text(tr('mode.${mode.name}.examples'), style: text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Local or cloud. Cloud is shown disabled.
class _StorageChoice extends StatelessWidget {
  const _StorageChoice();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      children: <Widget>[
        SageCard(
          selected: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(tr('storage.local.name'), style: text.titleSmall),
              const SizedBox(height: SageSpace.xs),
              Text(tr('storage.local.body'), style: text.bodyMedium),
            ],
          ),
        ),
        const SizedBox(height: SageSpace.sm),
        Opacity(
          opacity: 0.5,
          child: SageCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(tr('storage.cloud.name'), style: text.titleSmall),
                const SizedBox(height: SageSpace.xs),
                Text(tr('storage.cloud.notYet'), style: text.bodyMedium),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
