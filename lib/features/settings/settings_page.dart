import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/l10n/app_locales.dart';
import 'package:sielto/core/settings/local_settings.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/theme/theme_mode_controller.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/features/categories/categories_page.dart';
import 'package:sielto/features/dev/token_gallery_page.dart';
import 'package:sielto/features/settings/holidays_page.dart';
import 'package:sielto/features/settings/language_picker.dart';
import 'package:sielto/features/spaces/space_switcher_sheet.dart';

/// Profile and app settings.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode themeMode = ref.watch(themeModeProvider);
    final FeedDensity density = ref.watch(feedDensityProvider);

    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: AppBar(title: Text(tr('settings.title'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: SageSpace.md),
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(tr('settings.name')),
            subtitle: Text(
              ref.watch(nameProvider) ?? tr('settings.nameNotSet'),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editName(context, ref),
          ),
          SectionLabel(tr('settings.display')),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SageSpace.gutter,
              vertical: SageSpace.sm,
            ),
            child: LabelledField(
              label: tr('settings.theme'),
              child: SegmentedChoice<ThemeMode>(
                values: ThemeMode.values,
                selected: themeMode,
                labelOf: (ThemeMode mode) => tr('theme.${mode.name}'),
                onChanged: (ThemeMode mode) =>
                    ref.read(themeModeProvider.notifier).set(mode),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SageSpace.gutter,
              vertical: SageSpace.sm,
            ),
            child: LabelledField(
              label: tr('settings.feedDensity'),
              child: SegmentedChoice<FeedDensity>(
                values: FeedDensity.values,
                selected: density,
                labelOf: (FeedDensity value) => tr('density.${value.name}'),
                onChanged: (FeedDensity value) =>
                    ref.read(feedDensityProvider.notifier).set(value),
              ),
            ),
          ),
          SectionLabel(tr('settings.controlsAtBottom')),
          for (final ControlsScreen screen in ControlsScreen.values)
            SwitchListTile.adaptive(
              title: Text(tr('settings.controlsScreen.${screen.name}')),
              value: ref.watch(controlsAtBottomProvider).contains(screen),
              onChanged: (bool value) => ref
                  .read(controlsAtBottomProvider.notifier)
                  .set(screen, atBottom: value),
            ),
          // A sheet, not a segmented control: the list of languages can grow.
          ListTile(
            leading: const Icon(Icons.translate_outlined),
            title: Text(tr('settings.language')),
            subtitle: Text(AppLocales.resolve(context.locale).name),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLanguagePicker(context),
          ),
          const SizedBox(height: SageSpace.md),
          SectionLabel(tr('settings.data')),
          ListTile(
            leading: const Icon(Icons.dashboard_outlined),
            title: Text(tr('settings.spaces')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showSpaceSwitcher(context),
          ),
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: Text(tr('category.title')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext _) => const CategoriesPage(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.event_busy_outlined),
            title: Text(tr('holidays.title')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext _) => const HolidaysPage(),
              ),
            ),
          ),
          const SizedBox(height: SageSpace.md),
          SectionLabel(tr('settings.network')),
          SwitchListTile.adaptive(
            secondary: const Icon(Icons.wifi_off_outlined),
            title: Text(tr('settings.fullyOffline')),
            subtitle: Text(tr('settings.fullyOfflineHint')),
            value: ref.watch(offlineModeProvider),
            onChanged: (bool value) =>
                ref.read(offlineModeProvider.notifier).set(value: value),
          ),
          // Debug builds, or a release built with --dart-define=SIELTO_DEV=true.
          if (kDebugMode || const bool.fromEnvironment('SIELTO_DEV'))
            ListTile(
              leading: const Icon(Icons.science_outlined),
              title: const Text('Developer'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext _) => const TokenGalleryPage(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _editName(BuildContext context, WidgetRef ref) async {
  final String? typed = await showDialog<String>(
    context: context,
    builder: (BuildContext context) =>
        _NameDialog(initial: ref.read(nameProvider) ?? ''),
  );
  if (typed != null) await ref.read(nameProvider.notifier).set(typed);
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});

  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: context.sage.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(SageRadius.card),
    ),
    title: Text(
      tr('settings.name'),
      style: Theme.of(context).textTheme.titleMedium,
    ),
    content: TextField(
      controller: _controller,
      autofocus: true,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(hintText: tr('onboarding.nameHint')),
      onSubmitted: (String value) => Navigator.of(context).pop(value),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(tr('common.cancel')),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(_controller.text),
        child: Text(tr('common.save')),
      ),
    ],
  );
}
