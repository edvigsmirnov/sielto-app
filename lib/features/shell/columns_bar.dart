import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/dashboard/period_selector.dart';
import 'package:sielto/features/settings/settings_page.dart';
import 'package:sielto/features/settings/space_settings_page.dart';
import 'package:sielto/features/spaces/space_avatar.dart';

/// Above the wide layouts: the Space, its period, Space settings, profile.
class ColumnsBar extends ConsumerWidget {
  const ColumnsBar({
    required this.onOpen,
    required this.onSpaces,
    this.toggles = true,
    super.key,
  });

  /// Opens the list of Spaces.
  final VoidCallback onSpaces;

  /// Shows the buttons that collapse the side columns.
  final bool toggles;

  /// Opens a page in the Calendar column, under its buttons.
  final ValueChanged<Widget> onOpen;

  static const double height = 64;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SageColors sage = context.sage;
    final Space? space = ref.watch(currentSpaceProvider);
    final String? initial = ref.watch(profileInitialProvider);
    final ColumnsLayout layout = ref.watch(columnsLayoutProvider);
    final ColumnsLayoutController columns = ref.read(
      columnsLayoutProvider.notifier,
    );
    if (space == null) return const SizedBox(height: height);

    return Material(
      color: sage.canvas,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: SageSpace.md),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: sage.hairline)),
        ),
        child: FocusTraversalGroup(
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 300,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Builder(
                    builder: (BuildContext button) => TextButton.icon(
                      onPressed: onSpaces,
                      icon: SpaceAvatar(
                        spaceId: space.id,
                        title: space.title,
                        size: 32,
                      ),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              space.title,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          const SizedBox(width: SageSpace.xs),
                          Icon(
                            Icons.unfold_more,
                            size: 18,
                            color: sage.inkLabel,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: space.budgetMode == BudgetMode.incomeDriven
                    ? const Center(
                        child: SizedBox(
                          width: 420,
                          child: PeriodSelector(swipe: false),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              SizedBox(
                width: 300,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    if (toggles) ...<Widget>[
                      IconButton(
                        tooltip: tr('shell.dashboardColumn'),
                        isSelected: !layout.dashboardCollapsed,
                        onPressed: columns.toggleDashboard,
                        icon: Transform.flip(
                          flipX: true,
                          child: const Icon(Icons.view_sidebar_outlined),
                        ),
                        selectedIcon: Transform.flip(
                          flipX: true,
                          child: const Icon(Icons.view_sidebar),
                        ),
                      ),
                      IconButton(
                        tooltip: tr('shell.calendarColumn'),
                        isSelected: !layout.calendarCollapsed,
                        onPressed: columns.toggleCalendar,
                        icon: const Icon(Icons.view_sidebar_outlined),
                        selectedIcon: const Icon(Icons.view_sidebar),
                      ),
                      const SizedBox(width: SageSpace.sm),
                    ],
                    SoftIconButton(
                      size: 44,
                      icon: Icons.settings_outlined,
                      tooltip: tr('spaceSettings.title'),
                      onTap: () => onOpen(SpaceSettingsPage(space: space)),
                    ),
                    const SizedBox(width: SageSpace.sm),
                    IconButton(
                      tooltip: tr('settings.title'),
                      onPressed: () => onOpen(const SettingsPage()),
                      icon: CircleAvatar(
                        radius: 18,
                        backgroundColor: sage.accentTintAlt,
                        foregroundColor: sage.accentStrong,
                        child: initial == null
                            ? const Icon(Icons.person_outline, size: 18)
                            : Text(initial),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
