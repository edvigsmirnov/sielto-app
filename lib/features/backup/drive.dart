import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/backup/backup_file.dart';
import 'package:sielto/core/backup/drive_backups.dart';
import 'package:sielto/core/settings/local_settings.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/leaf_loader.dart';
import 'package:sielto/features/security/recovery_key.dart';

/// OAuth clients of the Sielto Google Cloud project. The Android client is
/// matched by package name and signing key, so it has no id here.
abstract final class GoogleClients {
  static const String web =
      '674408649367-nuir51j8klmh3ujai2nhng8np54724o3.apps.googleusercontent.com';
  static const String desktop =
      '674408649367-bksgu30oehq6icpdq6ppe42o6jns3ido.apps.googleusercontent.com';

  /// Kept out of the public source; passed with --dart-define.
  static const String desktopSecret = String.fromEnvironment(
    'SIELTO_GOOGLE_DESKTOP_SECRET',
  );
}

/// Android always; desktop only in builds that carry the client secret.
bool get driveSupported =>
    Platform.isAndroid ||
    ((Platform.isWindows || Platform.isLinux) &&
        GoogleClients.desktopSecret.isNotEmpty);

/// Sign-in: `google_sign_in` on Android, a loopback OAuth flow on desktop.
class DriveAuth {
  const DriveAuth({this.storage = const FlutterSecureStorage()});

  static const String _credentials = 'drive_credentials';
  static const List<String> _scopes = <String>[DriveBackups.scope];
  static Future<void>? _initialized;

  final FlutterSecureStorage storage;

  static ClientId get _desktopId =>
      ClientId(GoogleClients.desktop, GoogleClients.desktopSecret);

  /// Null when Drive is not authorized and [interactive] is false.
  Future<http.Client?> client({required bool interactive}) async {
    if (Platform.isAndroid) {
      await (_initialized ??= GoogleSignIn.instance.initialize(
        serverClientId: GoogleClients.web,
      ));
      final GoogleSignInAuthorizationClient authorization =
          GoogleSignIn.instance.authorizationClient;
      GoogleSignInClientAuthorization? granted = await authorization
          .authorizationForScopes(_scopes);
      if (granted == null && interactive) {
        granted = await authorization.authorizeScopes(_scopes);
      }
      if (granted == null) return null;
      return authenticatedClient(
        http.Client(),
        AccessCredentials(
          AccessToken(
            'Bearer',
            granted.accessToken,
            DateTime.now().toUtc().add(const Duration(minutes: 50)),
          ),
          null,
          _scopes,
        ),
      );
    }

    AccessCredentials? credentials = await _read();
    if (credentials == null) {
      if (!interactive) return null;
      credentials = await obtainAccessCredentialsViaUserConsent(
        _desktopId,
        _scopes,
        http.Client(),
        _openBrowser,
      );
      await _write(credentials);
    }
    final AutoRefreshingAuthClient client = autoRefreshingClient(
      _desktopId,
      credentials,
      http.Client(),
    );
    client.credentialUpdates.listen(_write);
    return client;
  }

  Future<void> disconnect() async {
    if (Platform.isAndroid) {
      await GoogleSignIn.instance.disconnect();
      return;
    }
    try {
      await storage.delete(key: _credentials);
    } on Exception {
      // No keyring: nothing was stored.
    }
  }

  Future<AccessCredentials?> _read() async {
    try {
      final String? raw = await storage.read(key: _credentials);
      return raw == null
          ? null
          : AccessCredentials.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Exception {
      return null;
    }
  }

  Future<void> _write(AccessCredentials credentials) async {
    try {
      await storage.write(
        key: _credentials,
        value: jsonEncode(credentials.toJson()),
      );
    } on Exception {
      // No keyring: the sign-in lasts for this run.
    }
  }

  static void _openBrowser(String url) {
    if (Platform.isWindows) {
      Process.run('rundll32', <String>['url.dll,FileProtocolHandler', url]);
    } else {
      Process.run('xdg-open', <String>[url]);
    }
  }
}

/// Null [email] when Drive backup is off.
typedef DriveState = ({String? email, DateTime? lastBackup, bool busy});

/// Daily snapshot: checked at start and on every resume, since neither
/// desktop nor this build schedules background work.
class DriveController extends Notifier<DriveState> with WidgetsBindingObserver {
  static const Duration interval = Duration(hours: 24);

  LocalSettings get _settings => ref.read(localSettingsProvider);

  @override
  DriveState build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() => WidgetsBinding.instance.removeObserver(this));
    final LocalSettings settings = ref.watch(localSettingsProvider);
    Future<void>.microtask(_autoBackUp);
    return (
      email: settings.driveEmail,
      lastBackup: settings.driveLastBackup,
      busy: false,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_autoBackUp());
  }

  /// Signs in and makes the first snapshot. False when cancelled.
  Future<bool> connect() async {
    final http.Client? client;
    try {
      client = await const DriveAuth().client(interactive: true);
    } on Exception {
      return false;
    }
    if (client == null) return false;
    final String email =
        await DriveBackups(client).accountEmail() ?? 'Google Drive';
    await _settings.setDriveEmail(email);
    state = (email: email, lastBackup: state.lastBackup, busy: false);
    await backUp(interactive: true);
    return true;
  }

  Future<void> disconnect() async {
    await const DriveAuth().disconnect();
    await _settings.setDriveEmail(null);
    await _settings.setDriveLastBackup(null);
    state = (email: null, lastBackup: null, busy: false);
  }

  /// False when Drive is off, the sign-in is gone, or the Recovery Key is
  /// not at hand.
  Future<bool> backUp({required bool interactive}) async {
    if (state.email == null || state.busy) return false;
    final String? recoveryKey = await ref
        .read(keyManagerProvider)
        .storedRecoveryKey();
    if (recoveryKey == null) return false;
    state = (email: state.email, lastBackup: state.lastBackup, busy: true);
    try {
      final http.Client? client = await const DriveAuth().client(
        interactive: interactive,
      );
      if (client == null) return false;
      final Uint8List bytes = await BackupFile.seal(
        await ref.read(repositoriesProvider).backup.export(),
        recoveryKey,
      );
      final DateTime now = DateTime.now();
      await DriveBackups(client).upload(bytes, now);
      await _settings.setDriveLastBackup(now);
      state = (email: state.email, lastBackup: now, busy: false);
      return true;
    } on Exception {
      return false;
    } finally {
      if (state.busy) {
        state = (email: state.email, lastBackup: state.lastBackup, busy: false);
      }
    }
  }

  Future<void> _autoBackUp() async {
    final DateTime? last = state.lastBackup;
    if (state.email == null ||
        (last != null && DateTime.now().difference(last) < interval)) {
      return;
    }
    await backUp(interactive: false);
  }
}

final NotifierProvider<DriveController, DriveState> driveProvider =
    NotifierProvider<DriveController, DriveState>(DriveController.new);

/// Snapshots in Drive; pops with the chosen one's bytes.
class DriveSnapshotsPage extends StatefulWidget {
  const DriveSnapshotsPage({super.key});

  @override
  State<DriveSnapshotsPage> createState() => _DriveSnapshotsPageState();
}

class _DriveSnapshotsPageState extends State<DriveSnapshotsPage> {
  DriveBackups? _drive;
  List<DriveSnapshot>? _snapshots;
  bool _failed = false;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final http.Client? client = await const DriveAuth().client(
        interactive: true,
      );
      if (client == null) throw const DriveException(401);
      final DriveBackups drive = DriveBackups(client);
      final List<DriveSnapshot> snapshots = await drive.list();
      if (mounted) {
        setState(() {
          _drive = drive;
          _snapshots = snapshots;
        });
      }
    } on Exception {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _pick(DriveSnapshot snapshot) async {
    setState(() => _downloading = true);
    try {
      final Uint8List bytes = await _drive!.download(snapshot.id);
      if (mounted) Navigator.of(context).pop(bytes);
    } on Exception {
      if (mounted) {
        setState(() {
          _downloading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<DriveSnapshot>? snapshots = _snapshots;
    final String locale = context.locale.toString();
    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: AppBar(title: Text(tr('drive.snapshotsTitle'))),
      body: _failed
          ? Center(child: Text(tr('drive.failed')))
          : snapshots == null || _downloading
          ? const Center(child: LeafLoader())
          : snapshots.isEmpty
          ? Center(child: Text(tr('drive.none')))
          : ListView(
              children: <Widget>[
                for (final DriveSnapshot s in snapshots)
                  ListTile(
                    leading: const Icon(Icons.cloud_outlined),
                    title: Text(
                      DateFormat.yMMMd(locale)
                          .add_Hm()
                          .format(s.createdAt.toLocal()),
                    ),
                    subtitle: Text(
                      tr(
                        'drive.kb',
                        args: <String>['${(s.size / 1024).ceil()}'],
                      ),
                    ),
                    onTap: () => _pick(s),
                  ),
              ],
            ),
    );
  }
}
