import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

enum FeedDensity {
  /// Amount and title on one line.
  compact,
  standard,

  /// Adds category and status on a second line.
  spacious,
}

/// Device-local settings, never uploaded. In shared_preferences so the theme
/// is readable before the database opens.
class LocalSettings {
  LocalSettings._(this._prefs, this.userId);

  static const Uuid _uuid = Uuid();

  static const String _keyUserId = 'user_id';
  static const String _keyName = 'nickname';
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyFeedDensity = 'feed_density';
  static const String _keyCurrencyCode = 'currency_code';
  static const String _keyCurrentSpaceId = 'current_space_id';
  static const String _keyDefaultCountry = 'default_country_code';
  static const String _keyHolidayConsent = 'holiday_fetch_consent';
  static const String _keyOfflineMode = 'fully_offline';
  static const String _keyControlsAtBottom = 'controls_at_bottom';

  final SharedPreferences _prefs;

  /// Generated at first install; author of every edit.
  final String userId;

  /// Creates the user id on first launch.
  static Future<LocalSettings> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_keyUserId);
    if (id == null) {
      id = _uuid.v4();
      await prefs.setString(_keyUserId, id);
    }
    return LocalSettings._(prefs, id);
  }

  /// Null when skipped at onboarding.
  String? get name => _prefs.getString(_keyName);

  Future<void> setName(String? value) async {
    final String? trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await _prefs.remove(_keyName);
      return;
    }
    await _prefs.setString(_keyName, trimmed);
  }

  ThemeMode get themeMode =>
      _readEnum(_keyThemeMode, ThemeMode.values) ?? ThemeMode.system;

  Future<void> setThemeMode(ThemeMode mode) =>
      _prefs.setString(_keyThemeMode, mode.name);

  FeedDensity get feedDensity =>
      _readEnum(_keyFeedDensity, FeedDensity.values) ?? FeedDensity.standard;

  Future<void> setFeedDensity(FeedDensity density) =>
      _prefs.setString(_keyFeedDensity, density.name);

  /// Default currency for new Spaces. Null until onboarding sets it.
  String? get currencyCode => _prefs.getString(_keyCurrencyCode);

  Future<void> setCurrencyCode(String code) =>
      _prefs.setString(_keyCurrencyCode, code);

  /// Cleared when that Space is gone.
  String? get currentSpaceId => _prefs.getString(_keyCurrentSpaceId);

  Future<void> setCurrentSpaceId(String? id) async {
    if (id == null) {
      await _prefs.remove(_keyCurrentSpaceId);
      return;
    }
    await _prefs.setString(_keyCurrentSpaceId, id);
  }

  /// Holiday country for Spaces without their own. Null ignores holidays.
  String? get defaultCountryCode => _prefs.getString(_keyDefaultCountry);

  Future<void> setDefaultCountryCode(String? code) async {
    if (code == null || code.trim().isEmpty) {
      await _prefs.remove(_keyDefaultCountry);
      return;
    }
    await _prefs.setString(_keyDefaultCountry, code.trim().toUpperCase());
  }

  /// Null means not asked yet.
  bool? get holidayFetchAllowed => _prefs.getBool(_keyHolidayConsent);

  Future<void> setHolidayFetchAllowed({required bool? allowed}) async {
    if (allowed == null) {
      await _prefs.remove(_keyHolidayConsent);
      return;
    }
    await _prefs.setBool(_keyHolidayConsent, allowed);
  }

  /// When true, nothing reaches the network.
  bool get fullyOffline => _prefs.getBool(_keyOfflineMode) ?? false;

  Future<void> setFullyOffline({required bool value}) =>
      _prefs.setBool(_keyOfflineMode, value);

  /// Screens with period controls above the bottom bar.
  Set<ControlsScreen> get controlsAtBottom {
    final List<String>? names = _prefs.getStringList(_keyControlsAtBottom);
    if (names == null) return const <ControlsScreen>{ControlsScreen.calendar};
    return <ControlsScreen>{
      for (final ControlsScreen s in ControlsScreen.values)
        if (names.contains(s.name)) s,
    };
  }

  Future<void> setControlsAtBottom(Set<ControlsScreen> screens) =>
      _prefs.setStringList(_keyControlsAtBottom, <String>[
        for (final ControlsScreen s in screens) s.name,
      ]);

  /// Stored by name, not index.
  T? _readEnum<T extends Enum>(String key, List<T> values) {
    final String? name = _prefs.getString(key);
    if (name == null) return null;
    for (final T value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

enum ControlsScreen { dashboard, feed, calendar }
