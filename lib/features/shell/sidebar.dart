import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';

/// The one-column layout's navigation between the three screens; it narrows
/// to icons.
class Sidebar extends ConsumerWidget {
  const Sidebar({required this.index, required this.onSelect, super.key});

  final int index;
  final ValueChanged<int> onSelect;

  static const double width = 248;
  static const double compactWidth = 72;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SageColors sage = context.sage;
    final bool compact = ref.watch(compactSidebarProvider);

    return Material(
      color: sage.canvas,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: compact ? compactWidth : width,
        child: SafeArea(
          right: false,
          child: FocusTraversalGroup(
            child: Padding(
              padding: const EdgeInsets.all(SageSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final (int i, (IconData, IconData, String) d)
                      in <(IconData, IconData, String)>[
                        (
                          Icons.donut_small_outlined,
                          Icons.donut_small,
                          'nav.dashboard',
                        ),
                        (Icons.list_alt_outlined, Icons.list_alt, 'nav.feed'),
                        (
                          Icons.calendar_month_outlined,
                          Icons.calendar_month,
                          'nav.calendar',
                        ),
                      ].indexed)
                    _Item(
                      icon: i == index ? d.$2 : d.$1,
                      label: tr(d.$3),
                      compact: compact,
                      selected: i == index,
                      onTap: () => onSelect(i),
                    ),
                  const Spacer(),
                  _Item(
                    icon: compact
                        ? Icons.keyboard_double_arrow_right
                        : Icons.keyboard_double_arrow_left,
                    label: tr(
                      compact ? 'shell.expandSidebar' : 'shell.collapseSidebar',
                    ),
                    compact: compact,
                    onTap: ref.read(compactSidebarProvider.notifier).toggle,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.label,
    required this.compact,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final bool compact;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final Color ink = selected ? sage.ink : sage.inkSecondary;
    final Widget body = Material(
      color: selected ? sage.accentTintAlt : Colors.transparent,
      borderRadius: BorderRadius.circular(SageRadius.button),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SageRadius.button),
        child: SizedBox(
          height: 48,
          child: Row(
            children: <Widget>[
              SizedBox(width: 48, child: Icon(icon, color: ink)),
              if (!compact)
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(color: sage.ink),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: SageSpace.xs),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: compact ? Tooltip(message: label, child: body) : body,
      ),
    );
  }
}
