import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/features/calendar/calendar_page.dart';
import 'package:sielto/features/calendar/calendar_scope.dart';
import 'package:sielto/features/dashboard/dashboard_page.dart';
import 'package:sielto/features/feed/feed_page.dart';
import 'package:sielto/features/feed/feed_selection.dart';
import 'package:sielto/features/shell/shell_tab.dart';

/// Dashboard, Feed and Calendar, switched by the bottom bar or a swipe.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  late final PageController _controller = PageController(initialPage: _index);

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
    // Jumps over intermediate tabs.
    if (distance > 1) {
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

  static const int _feedTab = 1;

  static const int _calendarTab = 2;

  /// Back leaves Calendar zoom first, then returns to the Dashboard.
  void _back() {
    final FeedSelectionController selection = ref.read(
      feedSelectionProvider.notifier,
    );
    if (ref.read(feedSelectionProvider).isNotEmpty) {
      selection.clear();
      return;
    }
    if (_index == _calendarTab &&
        ref.read(calendarViewProvider.notifier).back()) {
      return;
    }
    if (_index != 0) _goTo(0);
  }

  @override
  Widget build(BuildContext context) {
    _resetOnSpaceChange();
    final int index = ref.watch(shellTabProvider);
    final bool selecting = ref.watch(feedSelectionProvider).isNotEmpty;
    return PopScope(
      canPop: index == 0 && !selecting,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: context.sage.surface,
        body: PageView(
          controller: _controller,
          // Feed rows own the horizontal swipe.
          physics: index == _feedTab
              ? const NeverScrollableScrollPhysics()
              : null,
          onPageChanged: _show,
          children: const <Widget>[
            _KeepAlive(child: DashboardPage()),
            _KeepAlive(child: FeedPage()),
            _KeepAlive(child: CalendarPage()),
          ],
        ),
        bottomNavigationBar: NavigationBar(
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
