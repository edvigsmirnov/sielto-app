import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:sielto/core/settings/local_settings.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/update/update_service.dart';

final FutureProvider<PackageInfo> appVersionProvider =
    FutureProvider<PackageInfo>((Ref ref) => PackageInfo.fromPlatform());

class UpdateState {
  const UpdateState({
    required this.enabled,
    required this.latest,
    required this.lastCheck,
    required this.dismissed,
    this.checking = false,
    this.failed = false,
  });

  /// Null until asked.
  final bool? enabled;
  final Release? latest;
  final DateTime? lastCheck;

  /// The version whose plate was closed.
  final String? dismissed;
  final bool checking;
  final bool failed;

  UpdateState copyWith({
    bool? enabled,
    String? dismissed,
    bool? checking,
    bool? failed,
  }) => UpdateState(
    enabled: enabled ?? this.enabled,
    latest: latest,
    lastCheck: lastCheck,
    dismissed: dismissed ?? this.dismissed,
    checking: checking ?? this.checking,
    failed: failed ?? this.failed,
  );
}

/// Checked at start and on every resume once a day, like the Drive snapshot.
class UpdateController extends Notifier<UpdateState>
    with WidgetsBindingObserver {
  LocalSettings get _settings => ref.read(localSettingsProvider);

  @override
  UpdateState build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() => WidgetsBinding.instance.removeObserver(this));
    final LocalSettings settings = ref.watch(localSettingsProvider);
    Future<void>.microtask(_autoCheck);
    if (Platform.isAndroid) unawaited(_dropInstalledApk());
    return UpdateState(
      enabled: settings.updateChecks,
      latest: _decode(settings.updateLatest),
      lastCheck: settings.updateLastCheck,
      dismissed: settings.updateDismissed,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_autoCheck());
  }

  Future<void> setEnabled({required bool value}) async {
    await _settings.setUpdateChecks(value: value);
    state = state.copyWith(enabled: value);
    if (value) await _autoCheck();
  }

  Future<void> dismiss(Release release) async {
    final String version = release.version.toString();
    await _settings.setUpdateDismissed(version);
    state = state.copyWith(dismissed: version);
  }

  /// Works with checks off; never in fully offline mode.
  Future<void> check() async {
    if (state.checking || ref.read(offlineModeProvider)) return;
    state = state.copyWith(checking: true, failed: false);
    final http.Client client = http.Client();
    try {
      final Version current = Version.parse(
        (await ref.read(appVersionProvider.future)).version,
      );
      final Release? latest = await UpdateService(client)
          .newest(preReleases: current.isPreRelease);
      final DateTime now = DateTime.now();
      await _settings.setUpdateLatest(_encode(latest));
      await _settings.setUpdateLastCheck(now);
      state = UpdateState(
        enabled: state.enabled,
        latest: latest,
        lastCheck: now,
        dismissed: state.dismissed,
      );
    } on Exception {
      state = state.copyWith(checking: false, failed: true);
    } on TypeError {
      state = state.copyWith(checking: false, failed: true);
    } finally {
      client.close();
    }
  }

  /// The APK from the last update, installed or abandoned by now.
  static Future<void> _dropInstalledApk() async {
    final Directory updates = Directory(
      p.join((await getTemporaryDirectory()).path, 'updates'),
    );
    if (updates.existsSync()) await updates.delete(recursive: true);
  }

  Future<void> _autoCheck() async {
    if (state.enabled ?? false) {
      if (checkDue(state.lastCheck, DateTime.now())) await check();
    }
  }

  static String? _encode(Release? r) => r == null
      ? null
      : jsonEncode(<String, String?>{
          'version': r.version.toString(),
          'notes': r.notes,
          'page': r.page.toString(),
          'apk': r.apk?.toString(),
        });

  static Release? _decode(String? json) {
    if (json == null) return null;
    final Map<String, Object?> r = jsonDecode(json) as Map<String, Object?>;
    final String? apk = r['apk'] as String?;
    return (
      version: Version.parse(r['version']! as String),
      notes: r['notes']! as String,
      page: Uri.parse(r['page']! as String),
      apk: apk == null ? null : Uri.parse(apk),
    );
  }
}

final NotifierProvider<UpdateController, UpdateState> updateProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);

/// The newest release when it is ahead of this build.
final Provider<Release?> availableUpdateProvider = Provider<Release?>((
  Ref ref,
) {
  final Release? latest = ref.watch(
    updateProvider.select((UpdateState s) => s.latest),
  );
  final PackageInfo? info = ref.watch(appVersionProvider).value;
  return info == null
      ? null
      : availableUpdate(Version.parse(info.version), latest);
});

/// Android installs the APK itself; elsewhere the release page opens.
bool installsInApp(Release release) =>
    Platform.isAndroid && release.apk != null;

/// The APK download's share done, null while none runs.
class UpdateDownloadController extends Notifier<double?> {
  @override
  double? build() => null;

  /// Downloads into the cache and hands the APK to the installer. False
  /// when the download or the hand-over failed.
  Future<bool> install(Release release) async {
    final Uri? apk = release.apk;
    if (apk == null || state != null) return false;
    state = 0;
    final http.Client client = http.Client();
    try {
      final File file = File(
        p.join((await getTemporaryDirectory()).path, 'updates', 'sielto.apk'),
      );
      await UpdateService(client)
          .download(apk, file, (double done) => state = done);
      await const MethodChannel('sielto/window')
          .invokeMethod<void>('installApk', file.path);
      return true;
    } on Exception {
      return false;
    } finally {
      client.close();
      state = null;
    }
  }
}

final NotifierProvider<UpdateDownloadController, double?>
updateDownloadProvider = NotifierProvider<UpdateDownloadController, double?>(
  UpdateDownloadController.new,
);
