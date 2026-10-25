import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/settings/local_settings.dart';
import 'package:sielto/core/ui/layout.dart';

/// Overridden at startup.
final Provider<LocalSettings> localSettingsProvider = Provider<LocalSettings>(
  (Ref ref) => throw StateError('localSettingsProvider was not overridden'),
);

final Provider<String> userIdProvider = Provider<String>(
  (Ref ref) => ref.watch(localSettingsProvider).userId,
);

class NameController extends Notifier<String?> {
  @override
  String? build() => ref.watch(localSettingsProvider).name;

  Future<void> set(String? name) async {
    final LocalSettings settings = ref.read(localSettingsProvider);
    await settings.setName(name);
    state = settings.name;
  }
}

/// Null when not set.
final NotifierProvider<NameController, String?> nameProvider =
    NotifierProvider<NameController, String?>(NameController.new);

/// First letter of the name. Null without a name.
final Provider<String?> profileInitialProvider = Provider<String?>((Ref ref) {
  final String? name = ref.watch(nameProvider)?.trim();
  if (name == null || name.isEmpty) return null;
  return name.characters.first.toUpperCase();
});

class FeedDensityController extends Notifier<FeedDensity> {
  @override
  FeedDensity build() => ref.watch(localSettingsProvider).feedDensity;

  Future<void> set(FeedDensity density) async {
    await ref.read(localSettingsProvider).setFeedDensity(density);
    state = density;
  }
}

final NotifierProvider<FeedDensityController, FeedDensity> feedDensityProvider =
    NotifierProvider<FeedDensityController, FeedDensity>(
      FeedDensityController.new,
    );

/// Holiday country for Spaces without their own.
class DefaultCountryController extends Notifier<String?> {
  @override
  String? build() => ref.watch(localSettingsProvider).defaultCountryCode;

  /// A region of another country is dropped.
  Future<void> set(String? code) async {
    await ref.read(localSettingsProvider).setDefaultCountryCode(code);
    final String? region = ref.read(holidayRegionProvider);
    if (region != null && (code == null || !region.startsWith('$code-'))) {
      await ref.read(holidayRegionProvider.notifier).set(null);
    }
    state = code;
  }
}

class HolidayRegionController extends Notifier<String?> {
  @override
  String? build() => ref.watch(localSettingsProvider).holidayRegion;

  Future<void> set(String? code) async {
    await ref.read(localSettingsProvider).setHolidayRegion(code);
    state = code;
  }
}

final NotifierProvider<HolidayRegionController, String?> holidayRegionProvider =
    NotifierProvider<HolidayRegionController, String?>(
      HolidayRegionController.new,
    );

final NotifierProvider<DefaultCountryController, String?>
defaultCountryProvider = NotifierProvider<DefaultCountryController, String?>(
  DefaultCountryController.new,
);

/// Null means not asked yet.
class HolidayConsentController extends Notifier<bool?> {
  @override
  bool? build() => ref.watch(localSettingsProvider).holidayFetchAllowed;

  Future<void> set({required bool? allowed}) async {
    await ref
        .read(localSettingsProvider)
        .setHolidayFetchAllowed(allowed: allowed);
    state = allowed;
  }
}

final NotifierProvider<HolidayConsentController, bool?> holidayConsentProvider =
    NotifierProvider<HolidayConsentController, bool?>(
      HolidayConsentController.new,
    );

/// When true, nothing reaches the network.
class OfflineModeController extends Notifier<bool> {
  @override
  bool build() => ref.watch(localSettingsProvider).fullyOffline;

  Future<void> set({required bool value}) async {
    await ref.read(localSettingsProvider).setFullyOffline(value: value);
    state = value;
  }
}

final NotifierProvider<OfflineModeController, bool> offlineModeProvider =
    NotifierProvider<OfflineModeController, bool>(OfflineModeController.new);

class ControlsAtBottomController extends Notifier<Set<ControlsScreen>> {
  @override
  Set<ControlsScreen> build() =>
      ref.watch(localSettingsProvider).controlsAtBottom;

  Future<void> set(ControlsScreen screen, {required bool atBottom}) async {
    final Set<ControlsScreen> next = <ControlsScreen>{...state};
    atBottom ? next.add(screen) : next.remove(screen);
    await ref.read(localSettingsProvider).setControlsAtBottom(next);
    state = next;
  }
}

final NotifierProvider<ControlsAtBottomController, Set<ControlsScreen>>
controlsAtBottomProvider =
    NotifierProvider<ControlsAtBottomController, Set<ControlsScreen>>(
      ControlsAtBottomController.new,
    );

/// Wide windows ignore the setting: they have no bottom bar.
bool controlsAtBottom(BuildContext context, WidgetRef ref, ControlsScreen s) =>
    !isWide(context) && ref.watch(controlsAtBottomProvider).contains(s);

class ThreeColumnsController extends Notifier<bool> {
  @override
  bool build() => ref.watch(localSettingsProvider).threeColumns;

  Future<void> set({required bool value}) async {
    await ref.read(localSettingsProvider).setThreeColumns(value: value);
    state = value;
  }
}

final NotifierProvider<ThreeColumnsController, bool> threeColumnsProvider =
    NotifierProvider<ThreeColumnsController, bool>(ThreeColumnsController.new);

/// Dashboard and Calendar in the three-column layout: widths, and whether
/// each is collapsed to a rail.
@immutable
class ColumnsLayout {
  const ColumnsLayout({
    this.dashboard = 400,
    this.calendar = 480,
    this.dashboardCollapsed = false,
    this.calendarCollapsed = false,
  });

  factory ColumnsLayout.decode(List<String>? v) {
    if (v == null || v.length < 4) return const ColumnsLayout();
    return ColumnsLayout(
      dashboard: double.tryParse(v[0]) ?? 400,
      calendar: double.tryParse(v[1]) ?? 480,
      dashboardCollapsed: v[2] == '1',
      calendarCollapsed: v[3] == '1',
    );
  }

  static const double min = 320;
  static const double max = 720;

  final double dashboard;
  final double calendar;
  final bool dashboardCollapsed;
  final bool calendarCollapsed;

  ColumnsLayout copyWith({
    double? dashboard,
    double? calendar,
    bool? dashboardCollapsed,
    bool? calendarCollapsed,
  }) => ColumnsLayout(
    dashboard: (dashboard ?? this.dashboard).clamp(min, max),
    calendar: (calendar ?? this.calendar).clamp(min, max),
    dashboardCollapsed: dashboardCollapsed ?? this.dashboardCollapsed,
    calendarCollapsed: calendarCollapsed ?? this.calendarCollapsed,
  );

  List<String> encode() => <String>[
    '$dashboard',
    '$calendar',
    if (dashboardCollapsed) '1' else '0',
    if (calendarCollapsed) '1' else '0',
  ];
}

class ColumnsLayoutController extends Notifier<ColumnsLayout> {
  @override
  ColumnsLayout build() =>
      ColumnsLayout.decode(ref.watch(localSettingsProvider).columnsLayout);

  /// While dragging; [save] keeps it.
  void drag({double dashboard = 0, double calendar = 0}) =>
      state = state.copyWith(
        dashboard: state.dashboard + dashboard,
        calendar: state.calendar + calendar,
      );

  Future<void> toggleDashboard() {
    state = state.copyWith(dashboardCollapsed: !state.dashboardCollapsed);
    return save();
  }

  Future<void> toggleCalendar() {
    state = state.copyWith(calendarCollapsed: !state.calendarCollapsed);
    return save();
  }

  Future<void> reset() {
    state = const ColumnsLayout();
    return ref.read(localSettingsProvider).setColumnsLayout(null);
  }

  Future<void> save() =>
      ref.read(localSettingsProvider).setColumnsLayout(state.encode());
}

final NotifierProvider<ColumnsLayoutController, ColumnsLayout>
columnsLayoutProvider =
    NotifierProvider<ColumnsLayoutController, ColumnsLayout>(
      ColumnsLayoutController.new,
    );

class CompactSidebarController extends Notifier<bool> {
  @override
  bool build() => ref.watch(localSettingsProvider).compactSidebar;

  Future<void> toggle() async {
    state = !state;
    await ref.read(localSettingsProvider).setCompactSidebar(value: state);
  }
}

final NotifierProvider<CompactSidebarController, bool> compactSidebarProvider =
    NotifierProvider<CompactSidebarController, bool>(
      CompactSidebarController.new,
    );

class TickHintSeenController extends Notifier<bool> {
  @override
  bool build() => ref.watch(localSettingsProvider).tickHintSeen;

  Future<void> dismiss() async {
    await ref.read(localSettingsProvider).setTickHintSeen();
    state = true;
  }
}

final NotifierProvider<TickHintSeenController, bool> tickHintSeenProvider =
    NotifierProvider<TickHintSeenController, bool>(TickHintSeenController.new);

class BackupPlateClosedController extends Notifier<bool> {
  @override
  bool build() => ref.watch(localSettingsProvider).backupPlateClosed;

  Future<void> close() async {
    await ref.read(localSettingsProvider).setBackupPlateClosed();
    state = true;
  }
}

final NotifierProvider<BackupPlateClosedController, bool>
backupPlateClosedProvider = NotifierProvider<BackupPlateClosedController, bool>(
  BackupPlateClosedController.new,
);

class VanishedSpacesController extends Notifier<List<String>> {
  @override
  List<String> build() => ref.watch(localSettingsProvider).vanishedSpaces;

  Future<void> add(Iterable<String> ids) => _set(<String>{...state, ...ids});

  Future<void> remove(String id) =>
      _set(state.where((String s) => s != id).toSet());

  Future<void> _set(Set<String> ids) async {
    await ref.read(localSettingsProvider).setVanishedSpaces(ids.toList());
    state = ids.toList();
  }
}

/// Shared Spaces that left the cloud; each asks keep or delete once.
final NotifierProvider<VanishedSpacesController, List<String>>
vanishedSpacesProvider =
    NotifierProvider<VanishedSpacesController, List<String>>(
      VanishedSpacesController.new,
    );

class QuietSpacesController extends Notifier<Set<String>> {
  @override
  Set<String> build() => ref.watch(localSettingsProvider).quietSpaces.toSet();

  Future<void> set(String id, {required bool quiet}) async {
    final Set<String> ids = quiet
        ? <String>{...state, id}
        : state.where((String s) => s != id).toSet();
    await ref.read(localSettingsProvider).setQuietSpaces(ids.toList());
    state = ids;
  }
}

/// Spaces whose changes by others show no toast on this device.
final NotifierProvider<QuietSpacesController, Set<String>> quietSpacesProvider =
    NotifierProvider<QuietSpacesController, Set<String>>(
      QuietSpacesController.new,
    );
