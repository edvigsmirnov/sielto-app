import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/l10n/app_locales.dart';
import 'package:sielto/core/settings/local_settings.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/theme/theme_mode_controller.dart';
import 'package:sielto/core/ui/detail_host.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/core/ui/form_fields.dart';
import 'package:sielto/core/ui/layout.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/features/backup/backup_page.dart';
import 'package:sielto/features/categories/categories_page.dart';
import 'package:sielto/features/dev/token_gallery_page.dart';
import 'package:sielto/features/devices/devices_page.dart';
import 'package:sielto/features/feed/feed_columns.dart';
import 'package:sielto/features/security/security_page.dart';
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
      appBar: sageAppBar(context, title: Text(tr('settings.title'))),
      body: ListView(
        padding: scrollPadding(
          context,
          const EdgeInsets.symmetric(vertical: SageSpace.md),
        ),
        children: <Widget>[
          LinkTile(
            icon: Icons.person_outline,
            title: tr('settings.name'),
            subtitle: ref.watch(nameProvider) ?? tr('settings.nameNotSet'),
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
          // Wide, the Feed is a table with one row height.
          if (!isWide(context))
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
          if (isWide(context))
            SwitchListTile.adaptive(
              secondary: const Icon(Icons.view_column_outlined),
              title: Text(tr('settings.threeColumns')),
              subtitle: Text(tr('settings.threeColumnsBody')),
              value: ref.watch(threeColumnsProvider),
              onChanged: (bool value) =>
                  ref.read(threeColumnsProvider.notifier).set(value: value),
            ),
          if (isWide(context))
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: Text(tr('settings.resetLayout')),
              subtitle: Text(tr('settings.resetLayoutBody')),
              onTap: () {
                ref.read(columnsLayoutProvider.notifier).reset();
                ref.read(feedColumnsProvider.notifier).reset();
                ScaffoldMessenger.of(context).say(tr('settings.layoutReset'));
              },
            )
          else ...<Widget>[
            SectionLabel(tr('settings.controlsAtBottom')),
            for (final ControlsScreen screen in ControlsScreen.values)
              SwitchListTile.adaptive(
                title: Text(tr('settings.controlsScreen.${screen.name}')),
                value: ref.watch(controlsAtBottomProvider).contains(screen),
                onChanged: (bool value) => ref
                    .read(controlsAtBottomProvider.notifier)
                    .set(screen, atBottom: value),
              ),
          ],
          // A sheet, not a segmented control: the list of languages can grow.
          LinkTile(
            icon: Icons.translate_outlined,
            title: tr('settings.language'),
            subtitle: AppLocales.resolve(context.locale).name,
            onTap: () => showLanguagePicker(context),
          ),
          const SizedBox(height: SageSpace.md),
          SectionLabel(tr('settings.data')),
          LinkTile(
            icon: Icons.dashboard_outlined,
            title: tr('settings.spaces'),
            onTap: () => isWide(context)
                ? pushPage<void>(context, const SpacesPage())
                : showSpaceSwitcher(context),
          ),
          LinkTile(
            icon: Icons.label_outline,
            title: tr('category.title'),
            onTap: () => pushPage<void>(context, const CategoriesPage()),
          ),
          LinkTile(
            icon: Icons.event_busy_outlined,
            title: tr('holidays.title'),
            onTap: () => pushPage<void>(context, const HolidaysPage()),
          ),
          LinkTile(
            icon: Icons.lock_outline,
            title: tr('security.title'),
            onTap: () => pushPage<void>(context, const SecurityPage()),
          ),
          LinkTile(
            icon: Icons.backup_outlined,
            title: tr('backup.title'),
            onTap: () => pushPage<void>(context, const BackupPage()),
          ),
          LinkTile(
            icon: Icons.devices_outlined,
            title: tr('devices.listTitle'),
            onTap: () => pushPage<void>(context, const DevicesPage()),
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
            LinkTile(
              icon: Icons.science_outlined,
              title: 'Developer',
              onTap: () => pushPage<void>(context, const TokenGalleryPage()),
            ),
        ],
      ),
    );
  }
}

Future<void> _editName(BuildContext context, WidgetRef ref) async {
  final String? typed = await textDialog(
    context,
    title: tr('settings.name'),
    initial: ref.read(nameProvider) ?? '',
    hint: tr('onboarding.nameHint'),
    maxLength: TextLimits.name,
  );
  if (typed != null) await ref.read(nameProvider.notifier).set(typed);
}
