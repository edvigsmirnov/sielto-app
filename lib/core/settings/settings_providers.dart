import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/settings/local_settings.dart';

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
