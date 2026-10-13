import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/detail_host.dart';
import 'package:sielto/core/ui/layout.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/backup/drive.dart';
import 'package:sielto/features/calendar/calendar_page.dart';
import 'package:sielto/features/calendar/calendar_scope.dart';
import 'package:sielto/features/dashboard/dashboard_page.dart';
import 'package:sielto/features/feed/feed_filter.dart';
import 'package:sielto/features/feed/feed_page.dart';
import 'package:sielto/features/feed/feed_selection.dart';
import 'package:sielto/features/members/members_page.dart';
import 'package:sielto/features/payments/payment_form_page.dart';
import 'package:sielto/features/shell/columns_bar.dart';
import 'package:sielto/features/shell/shell_tab.dart';
import 'package:sielto/features/shell/sidebar.dart';
import 'package:sielto/features/spaces/space_switcher_sheet.dart';
import 'package:sielto/features/sync/activity.dart';
import 'package:sielto/features/sync/sync_controller.dart';

/// Dashboard, Feed and Calendar, switched by the bottom bar or, wide, the sidebar.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  late final PageController _controller = PageController(initialPage: _index);

  /// Keeps the tab pages' state when the sidebar comes and goes.
  final GlobalKey _pages = GlobalKey();

  /// Below the panel host, so Ctrl+N opens the form in the panel.
  final GlobalKey _inside = GlobalKey();

  /// A PageView rebuilt after the columns opens on the controller's first page.
  void _keepPage(int index) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controller.hasClients && _controller.page?.round() != index) {
          _controller.jumpToPage(index);
        }
      });

  /// One panel in both wide layouts, so what is open in it survives a switch.
  final GlobalKey _host = GlobalKey();

  void _openInPanel(Widget page) {
    if (_closed(_calendarRoutes, page)) return;
    DetailHost.push(_inside.currentContext ?? context, _route(page));
  }

  static MaterialPageRoute<void> _route(Widget page) => MaterialPageRoute<void>(
    settings: RouteSettings(name: '${page.runtimeType}'),
    builder: (BuildContext _) => page,
  );

  /// A second click on the button that opened a page closes it.
  bool _closed(ColumnRoutes routes, Widget page) {
    final List<Route<dynamic>> open = routes.stack
        .where((Route<dynamic> r) => r.isActive)
        .toList();
    if (open.length < 2 || open[1].settings.name != '${page.runtimeType}') {
      return false;
    }
    routes.navigator?.popUntil((Route<dynamic> r) => r.isFirst);
    return true;
  }

  final ColumnRoutes _dashboardRoutes = ColumnRoutes();

  /// The Dashboard column's navigator: Analytics and Spaces open in it.
  final GlobalKey<NavigatorState> _dashboard = GlobalKey<NavigatorState>();
  final ColumnRoutes _calendarRoutes = ColumnRoutes();

  /// One column: the Space list slides in on the left, under its button.
  final GlobalKey _spacesInside = GlobalKey();
  final ColumnRoutes _spacesRoutes = ColumnRoutes();

  /// Dashboard and Calendar keep navigators of their own: Analytics opens in
  /// the first, entries in the second.
  Widget _columns(BuildContext context) {
    final SageColors sage = context.sage;
    final ColumnsLayout layout = ref.watch(columnsLayoutProvider);
    final ColumnsLayoutController columns = ref.read(
      columnsLayoutProvider.notifier,
    );
    // A double click puts the widths back.
    Widget divider(ValueChanged<double> onDrag) => MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (DragUpdateDetails d) => onDrag(d.delta.dx),
        onHorizontalDragEnd: (DragEndDetails _) => columns.save(),
        onDoubleTap: () => columns.reset(),
        child: SizedBox(
          width: 9,
          child: Center(child: VerticalDivider(width: 1, color: sage.hairline)),
        ),
      ),
    );
    // Collapsed columns stay built, so what was open in them survives.
    Widget column({
      required bool shown,
      required double width,
      required Widget child,
      required Widget rail,
    }) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (!shown) rail,
        SizedBox(
          width: shown ? width : 0,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: width,
              maxWidth: width,
              child: ExcludeFocus(excluding: !shown, child: child),
            ),
          ),
        ),
      ],
    );

    return Column(
      children: <Widget>[
        ColumnsBar(
          onOpen: _openInPanel,
          onSpaces: () {
            if (_closed(_dashboardRoutes, const SpacesPage())) return;
            if (ref.read(columnsLayoutProvider).dashboardCollapsed) {
              ref.read(columnsLayoutProvider.notifier).toggleDashboard();
            }
            _dashboard.currentState?.pushAndRemoveUntil(
              _route(const SpacesPage()),
              (Route<dynamic> r) => r.isFirst,
            );
          },
        ),
        Expanded(
          child: DetailHost(
            key: _host,
            root: const CalendarPage(),
            observers: <NavigatorObserver>[_calendarRoutes],
            builder: (BuildContext _, Widget calendar, {required bool open}) {
              final bool calendarShown = !layout.calendarCollapsed || open;
              return Row(
                key: _inside,
                children: <Widget>[
                  column(
                    shown: !layout.dashboardCollapsed,
                    width: layout.dashboard,
                    rail: _Rail(
                      label: tr('nav.dashboard'),
                      icon: Icons.donut_small_outlined,
                      onTap: columns.toggleDashboard,
                    ),
                    child: ColumnHome(
                      label: tr('nav.dashboard'),
                      routes: _dashboardRoutes,
                      child: Navigator(
                        key: _dashboard,
                        observers: <NavigatorObserver>[_dashboardRoutes],
                        onGenerateRoute: (RouteSettings _) =>
                            PageRouteBuilder<void>(
                              pageBuilder: (
                                BuildContext _,
                                Animation<double> _,
                                Animation<double> _,
                              ) => const DashboardPage(),
                            ),
                      ),
                    ),
                  ),
                  if (layout.dashboardCollapsed)
                    VerticalDivider(width: 1, color: sage.hairline)
                  else
                    divider((double dx) => columns.drag(dashboard: dx)),
                  const Expanded(child: FeedPage()),
                  if (calendarShown)
                    divider((double dx) => columns.drag(calendar: -dx))
                  else
                    VerticalDivider(width: 1, color: sage.hairline),
                  column(
                    shown: calendarShown,
                    width: layout.calendar,
                    rail: _Rail(
                      label: tr('nav.calendar'),
                      icon: Icons.calendar_month_outlined,
                      onTap: columns.toggleCalendar,
                    ),
                    child: ColumnHome(
                      label: tr('nav.calendar'),
                      routes: _calendarRoutes,
                      child: calendar,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  int get _index => ref.read(shellTabProvider);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _show(int index) {
    ref.read(feedSelectionProvider.notifier).clear();
    ref.read(shellTabProvider.notifier).show(index);
  }

  void _goTo(int index) {
    final int distance = (index - _index).abs();
    _show(index);
    // Jumps over intermediate tabs, and always with reduced motion.
    if (distance > 1 || MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(index);
      return;
    }
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  /// A newly opened Space starts on its Dashboard.
  void _resetOnSpaceChange() {
    ref.listen<String?>(currentSpaceIdProvider, (
      String? previous,
      String? next,
    ) {
      if (previous == next || _index == 0) return;
      // After the frame: the notification can arrive mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _show(0);
        if (_controller.hasClients) _controller.jumpToPage(0);
      });
    });
  }

  /// Back leaves Calendar zoom first, then returns to the Dashboard.
  void _back() {
    final FeedSelectionController selection = ref.read(
      feedSelectionProvider.notifier,
    );
    if (ref.read(feedSelectionProvider).isNotEmpty) {
      selection.clear();
      return;
    }
    if (_index == ShellTabController.calendar &&
        ref.read(calendarViewProvider.notifier).back()) {
      return;
    }
    if (_index != 0) _goTo(0);
  }

  void _showDay(CalendarDate day) {
    ref.read(selectedDateProvider.notifier).select(day);
    ref.read(calendarViewProvider.notifier).select(CalendarView.day);
    _goTo(ShellTabController.calendar);
  }

  @override
  Widget build(BuildContext context) {
    _resetOnSpaceChange();
    // Keeps the daily Drive snapshot running while the shell is up.
    if (driveSupported) ref.watch(driveProvider);
    ref.listen(syncProvider.select((SyncState s) => s.unlinked), (
      bool? was,
      bool now,
    ) {
      if (now && was == false) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('devices.wasUnlinked')),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    });
    ref.listen(activityProvider, (List<Activity>? _, List<Activity> batch) {
      showActivity(context, ref, batch, onShow: _showDay);
    });
    ref.listen(retentionNoticeProvider, (
      List<RetentionNotice>? _,
      List<RetentionNotice> notices,
    ) {
      for (final RetentionNotice n in notices) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'members.retentionNotice',
                namedArgs: <String, String>{
                  'name': n.name ?? tr('members.noName'),
                  'space': n.spaceTitle,
                },
              ),
            ),
            duration: const Duration(seconds: 10),
            persist: false,
            action: SnackBarAction(
              label: tr('members.title'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext _) => MembersPage(spaceId: n.spaceId),
                ),
              ),
            ),
          ),
        );
      }
    });
    final int index = ref.watch(shellTabProvider);
    final bool selecting = ref.watch(feedSelectionProvider).isNotEmpty;
    final bool wide = isWide(context);
    final ShellMode mode = !wide
        ? ShellMode.phone
        : ref.watch(threeColumnsProvider) &&
              MediaQuery.sizeOf(context).width >= columnsBreakpoint
        ? ShellMode.columns
        : ShellMode.sidebar;
    _keepPage(index);
    _calendarRoutes.other = mode == ShellMode.columns
        ? _dashboardRoutes
        : _spacesRoutes;
    final String here = tr(
      'nav.${const <String>['dashboard', 'feed', 'calendar'][index]}',
    );
    final Widget pages = PageView(
      key: _pages,
      controller: _controller,
      physics: const NeverScrollableScrollPhysics(),
      children: <Widget>[
        for (final (int i, Widget page) in const <Widget>[
          DashboardPage(),
          FeedPage(),
          CalendarPage(),
        ].indexed)
          _KeepAlive(
            child: ExcludeFocus(excluding: i != index, child: page),
          ),
      ],
    );
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            openPaymentForm(_inside.currentContext ?? context),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          ref.read(feedFilterOpenProvider.notifier).set(open: true);
          if (mode != ShellMode.columns && index != 1) _goTo(1);
        },
      },
      // Keeps a focus inside the shell, so its shortcuts hear the keys.
      child: Focus(
        autofocus: true,
        skipTraversal: true,
        child: PopScope(
          canPop: index == 0 && !selecting,
          onPopInvokedWithResult: (bool didPop, Object? _) {
            if (!didPop) _back();
          },
          child: Scaffold(
            backgroundColor: context.sage.surface,
            body: ShellLayout(
              mode: mode,
              child: switch (mode) {
                ShellMode.phone => pages,
                ShellMode.sidebar => Column(
                  children: <Widget>[
                    ColumnsBar(
                      onOpen: _openInPanel,
                      onSpaces: () {
                        if (_closed(_spacesRoutes, const SpacesPage())) return;
                        DetailHost.push(
                          _spacesInside.currentContext ?? context,
                          _route(const SpacesPage()),
                        );
                      },
                      toggles: false,
                    ),
                    Expanded(
                      child: Row(
                        children: <Widget>[
                          Sidebar(index: index, onSelect: _goTo),
                          VerticalDivider(
                            width: 1,
                            color: context.sage.hairline,
                          ),
                          Expanded(
                            child: DetailHost(
                              root: const SizedBox.shrink(),
                              observers: <NavigatorObserver>[_spacesRoutes],
                              builder:
                                  (
                                    BuildContext _,
                                    Widget navigator, {
                                    required bool open,
                                  }) => SidePanel(
                                    key: _spacesInside,
                                    start: true,
                                    panel: ColumnHome(
                                      label: here,
                                      routes: _spacesRoutes,
                                      child: navigator,
                                    ),
                                    open: open,
                                    width: 440,
                                    child: DetailHost(
                                      key: _host,
                                      root: const CalendarPage(),
                                      observers: <NavigatorObserver>[
                                        _calendarRoutes,
                                      ],
                                      builder:
                                          (
                                            BuildContext _,
                                            Widget navigator, {
                                            required bool open,
                                          }) => SidePanel(
                                            key: _inside,
                                            panel: ColumnHome(
                                              label: here,
                                              routes: _calendarRoutes,
                                              child: navigator,
                                            ),
                                            open: open,
                                            width: 440,
                                            child: pages,
                                          ),
                                    ),
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                ShellMode.columns => _columns(context),
              },
            ),
            bottomNavigationBar: wide
                ? null
                : FocusTraversalGroup(
                    // A swipe up opens the Spaces switcher.
                    child: GestureDetector(
                      onVerticalDragEnd: (DragEndDetails d) {
                        if ((d.primaryVelocity ?? 0) < -300) {
                          showSpaceSwitcher(context);
                        }
                      },
                      child: NavigationBar(
                        selectedIndex: index,
                        onDestinationSelected: _goTo,
                        destinations: <NavigationDestination>[
                          NavigationDestination(
                            icon: const Icon(Icons.donut_small_outlined),
                            selectedIcon: const Icon(Icons.donut_small),
                            label: tr('nav.dashboard'),
                          ),
                          NavigationDestination(
                            icon: const Icon(Icons.list_alt_outlined),
                            selectedIcon: const Icon(Icons.list_alt),
                            label: tr('nav.feed'),
                          ),
                          NavigationDestination(
                            icon: const Icon(Icons.calendar_month_outlined),
                            selectedIcon: const Icon(Icons.calendar_month),
                            label: tr('nav.calendar'),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Keeps a tab alive while another is shown.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin<_KeepAlive> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// A collapsed column: its name, read upwards; a click expands it.
class _Rail extends StatelessWidget {
  const _Rail({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return Material(
      color: sage.canvas,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          child: Column(
            children: <Widget>[
              const SizedBox(height: SageSpace.md),
              Icon(icon, size: 20, color: sage.inkSecondary),
              const SizedBox(height: SageSpace.md),
              RotatedBox(
                quarterTurns: 3,
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: sage.inkSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
