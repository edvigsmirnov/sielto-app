import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/sync/cloud_identity.dart';
import 'package:sielto/core/sync/device_link.dart';
import 'package:sielto/core/sync/sync_worker.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/devices/device_name.dart';
import 'package:supabase/supabase.dart';

enum CloudResult { done, offlineMode, noNetwork, unlinked }

enum JoinResult { joined, wrongCode, tooManyAttempts, offlineMode, noNetwork }

typedef SyncState = ({bool unlinked, DateTime? lastSync});

typedef LinkedDevice = ({
  String id,
  String? name,
  DateTime lastSeen,
  bool current,
});

/// Syncs at start, on resume, after cloud edits and on server changes.
/// Sends nothing while fully offline or before any cloud use.
class SyncController extends Notifier<SyncState> with WidgetsBindingObserver {
  static const Duration _settle = Duration(seconds: 3);
  static const Duration _linkCheck = Duration(seconds: 60);

  late SupabaseClient _client;
  late CloudIdentity _identity;
  late SyncWorker _worker;
  Future<void> _tail = Future<void>.value();
  bool _queued = false;
  Timer? _debounce;
  Timer? _tick;
  RealtimeChannel? _channel;

  AppDatabase get _db => ref.read(databaseProvider);

  @override
  SyncState build() {
    final AppDatabase db = ref.watch(databaseProvider);
    final Future<String?> name = deviceName();
    _client = SupabaseProject.client();
    _identity = CloudIdentity(
      db: db,
      client: _client,
      userId: ref.watch(userIdProvider),
      deviceName: name,
    );
    _worker = SyncWorker(db: db, client: _client, deviceName: name);

    final StreamSubscription<int> edits = _pendingCount(db)
        .distinct()
        .where((int n) => n > 0)
        .listen((int _) => _soon());
    ref.listen(offlineModeProvider, (bool? _, bool offline) {
      if (offline) {
        _closeChannel();
      } else {
        unawaited(syncNow());
      }
    });
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _debounce?.cancel();
      _tick?.cancel();
      unawaited(edits.cancel());
      _closeChannel();
      unawaited(_identity.dispose());
      _client.dispose();
    });
    Future<void>.microtask(syncNow);
    _startTick();
    return (unlinked: false, lastSync: null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(syncNow());
      _startTick();
    } else {
      _tick?.cancel();
    }
  }

  /// Notices an unlink while the app stays open.
  void _startTick() {
    _tick?.cancel();
    _tick = Timer.periodic(_linkCheck, (Timer _) => unawaited(_checkLink()));
  }

  Future<void> _checkLink() => _serial(() async {
    if (ref.read(offlineModeProvider) || !await _usesCloud()) return;
    try {
      if (await _identity.ensure() == CloudAccess.unlinked ||
          !await _worker.touch()) {
        await _unlinked();
      }
    } on Exception catch (e) {
      debugPrint('sync: $e');
    }
  });

  /// Network trouble is left for the next run.
  Future<void> syncNow() {
    if (_queued) return _tail;
    _queued = true;
    return _serial(() async {
      _queued = false;
      if (ref.read(offlineModeProvider) || !await _usesCloud()) return;
      try {
        if (await _identity.ensure() == CloudAccess.unlinked) {
          await _unlinked();
          return;
        }
        _channel ??= _worker.watchRemote(_soon);
        if (!await _worker.syncAll()) {
          await _unlinked();
          return;
        }
        state = (unlinked: false, lastSync: DateTime.now());
      } on Exception catch (e) {
        debugPrint('sync: $e');
      }
    });
  }

  /// Cloud Spaces leave this device. One that never reached the cloud stays
  /// as a local Space: this device holds its only copy.
  Future<void> _unlinked() async {
    _closeChannel();
    state = (unlinked: true, lastSync: state.lastSync);
    final List<Space> cloud =
        await (_db.select(_db.spaces)..where(
              ($SpacesTable t) => t.storageMode.equalsValue(StorageMode.cloud),
            ))
            .get();
    for (final Space space in cloud) {
      if (space.serverReceivedAt == null) {
        await _makeLocal(space.id);
      } else {
        await ref.read(repositoriesProvider).spaces.deleteForever(space.id);
      }
    }
    await _identity.forget();
  }

  void _soon() {
    _debounce?.cancel();
    _debounce = Timer(_settle, () => unawaited(syncNow()));
  }

  void _closeChannel() {
    if (_channel case final RealtimeChannel channel) {
      unawaited(_client.removeChannel(channel));
    }
    _channel = null;
  }

  /// A one-time code for a new device; null with no network.
  Future<String?> newLinkCode() => _serial(() async {
    if (await _signIn() != CloudResult.done) return null;
    try {
      return await _client.rpc<String>('create_device_link_code');
    } on Exception {
      return null;
    }
  });

  /// Waits for the code to be claimed and seals the Recovery Key to the new
  /// device. False when the code went unclaimed or the network dropped.
  Future<bool> handOver(
    String? recoveryKey, {
    required bool Function() keepGoing,
  }) async {
    try {
      return await DeviceLink.handOver(
        _client,
        recoveryKey,
        keepGoing: keepGoing,
      );
    } on Exception {
      return false;
    }
  }

  /// Joins the account behind [code]. The Recovery Key is null when the
  /// other device does not send it in time.
  Future<({JoinResult result, String? userId, String? recoveryKey})> join(
    String code,
  ) async {
    if (ref.read(offlineModeProvider)) {
      return (result: JoinResult.offlineMode, userId: null, recoveryKey: null);
    }
    try {
      final SimpleKeyPair pair = await DeviceLink.newKeyPair();
      final String? userId = await _identity.link(
        code,
        await DeviceLink.publicKeyOf(pair),
      );
      if (userId == null) {
        return (result: JoinResult.wrongCode, userId: null, recoveryKey: null);
      }
      return (
        result: JoinResult.joined,
        userId: userId,
        recoveryKey: await DeviceLink.receive(_client, pair),
      );
    } on PostgrestException catch (e) {
      if (e.message == 'too_many_attempts') {
        return (
          result: JoinResult.tooManyAttempts,
          userId: null,
          recoveryKey: null,
        );
      }
      return (result: JoinResult.noNetwork, userId: null, recoveryKey: null);
    } on Exception {
      return (result: JoinResult.noNetwork, userId: null, recoveryKey: null);
    }
  }

  /// Uploads the Space and keeps it in step from now on.
  Future<CloudResult> moveToCloud(String spaceId) async {
    final CloudResult result = await _serial(() async {
      final CloudResult signedIn = await _signIn();
      if (signedIn != CloudResult.done) return signedIn;
      await _db.transaction(() async {
        await _db.customUpdate(
          "UPDATE spaces SET storage_mode = 'cloud', sync_status = 'pending' "
          'WHERE id = ?',
          variables: <Variable<Object>>[Variable<String>(spaceId)],
          updates: <TableInfo<dynamic, dynamic>>{_db.spaces},
        );
        for (final String table in SyncWorker.records) {
          await _db.customUpdate(
            "UPDATE $table SET sync_status = 'pending' "
            "WHERE space_id = ? AND sync_status <> 'rejected'",
            variables: <Variable<Object>>[Variable<String>(spaceId)],
            updates: <TableInfo<dynamic, dynamic>>{
              _db.allTables.firstWhere(
                (TableInfo<dynamic, dynamic> t) => t.actualTableName == table,
              ),
            },
          );
        }
      });
      return CloudResult.done;
    });
    if (result == CloudResult.done) unawaited(syncNow());
    return result;
  }

  /// Deletes the Space on the server. This device keeps it as a local Space;
  /// other devices keep a read-only archive.
  Future<CloudResult> moveToLocal(String spaceId) => _serial(() async {
    final CloudResult removed = await _removeFromServer(spaceId);
    if (removed != CloudResult.done) return removed;
    await _makeLocal(spaceId);
    return CloudResult.done;
  });

  Future<void> _makeLocal(String spaceId) => _db.customUpdate(
    "UPDATE spaces SET storage_mode = 'local', sync_status = 'none', "
    'server_received_at = NULL, synced_until = NULL WHERE id = ?',
    variables: <Variable<Object>>[Variable<String>(spaceId)],
    updates: <TableInfo<dynamic, dynamic>>{_db.spaces},
  );

  /// Deletes everything the cloud holds for this user and unlinks every
  /// device. Here, own cloud Spaces stay as local ones.
  Future<CloudResult> deleteCloudData() => _serial(() async {
    final CloudResult signedIn = await _signIn();
    if (signedIn != CloudResult.done) return signedIn;
    try {
      await _client.rpc<void>('delete_cloud_data');
    } on Exception {
      return CloudResult.noNetwork;
    }
    _closeChannel();
    final String me = ref.read(userIdProvider);
    final List<Space> cloud =
        await (_db.select(_db.spaces)..where(
              ($SpacesTable t) => t.storageMode.equalsValue(StorageMode.cloud),
            ))
            .get();
    for (final Space space in cloud) {
      if (space.ownerId == me) {
        await _makeLocal(space.id);
      } else {
        await ref.read(repositoriesProvider).spaces.deleteForever(space.id);
      }
    }
    await _identity.forget();
    return CloudResult.done;
  });

  /// This account's devices, most recently seen first.
  Future<({CloudResult result, List<LinkedDevice> devices})> devices() =>
      _serial(() async {
        final CloudResult signedIn = await _signIn();
        if (signedIn != CloudResult.done) {
          return (result: signedIn, devices: const <LinkedDevice>[]);
        }
        try {
          final String mine = await _identity.deviceId();
          final List<Map<String, dynamic>> rows = await _client
              .from('user_devices')
              .select('device_id, display_name, last_seen')
              .order('last_seen');
          return (
            result: CloudResult.done,
            devices: <LinkedDevice>[
              for (final Map<String, dynamic> r in rows.reversed)
                (
                  id: r['device_id'] as String,
                  name: r['display_name'] as String?,
                  lastSeen: DateTime.parse(r['last_seen'] as String),
                  current: r['device_id'] == mine,
                ),
            ],
          );
        } on Exception {
          return (
            result: CloudResult.noNetwork,
            devices: const <LinkedDevice>[],
          );
        }
      });

  Future<bool> renameDevice(String deviceId, String name) => _online(
    () => _client
        .from('user_devices')
        .update(<String, String>{'display_name': name})
        .eq('device_id', deviceId),
  );

  Future<bool> unlinkDevice(String deviceId) => _online(
    () => _client.rpc<void>(
      'unlink_device',
      params: <String, String>{'p_device_id': deviceId},
    ),
  );

  Future<bool> unlinkOtherDevices() =>
      _online(() => _client.rpc<void>('unlink_other_devices'));

  /// False with no network or no cloud access.
  Future<bool> _online(Future<void> Function() call) => _serial(() async {
    if (await _signIn() != CloudResult.done) return false;
    try {
      await call();
      return true;
    } on Exception {
      return false;
    }
  });

  /// The server copy goes first, or the next sync would bring it back.
  Future<CloudResult> deleteEverywhere(String spaceId) => _serial(() async {
    final CloudResult removed = await _removeFromServer(spaceId);
    if (removed != CloudResult.done) return removed;
    await ref.read(repositoriesProvider).spaces.deleteForever(spaceId);
    return CloudResult.done;
  });

  Future<CloudResult> _removeFromServer(String spaceId) async {
    final CloudResult signedIn = await _signIn();
    if (signedIn != CloudResult.done) return signedIn;
    try {
      await _client.from('spaces').delete().eq('id', spaceId);
    } on Exception {
      return CloudResult.noNetwork;
    }
    return CloudResult.done;
  }

  Future<CloudResult> _signIn() async {
    if (ref.read(offlineModeProvider)) return CloudResult.offlineMode;
    try {
      return switch (await _identity.ensure()) {
        CloudAccess.ready => CloudResult.done,
        CloudAccess.unlinked => CloudResult.unlinked,
      };
    } on Exception {
      return CloudResult.noNetwork;
    }
  }

  Future<T> _serial<T>(Future<T> Function() run) {
    final Future<T> next = _tail.then((void _) => run());
    _tail = next.then((T _) {}, onError: (Object _) {});
    return next;
  }

  Future<bool> _usesCloud() async =>
      await (_db.select(_db.cloudIdentity)
            ..where(($CloudIdentityTable t) => t.registered.equals(true)))
          .getSingleOrNull() !=
      null;

  static const String _spacesPending =
      "SELECT count(*) AS n FROM spaces WHERE storage_mode = 'cloud' "
      "AND sync_status = 'pending'";

  static String _pendingIn(String table) =>
      'SELECT count(*) AS n FROM $table JOIN spaces s '
      "ON s.id = $table.space_id AND s.storage_mode = 'cloud' "
      "WHERE $table.sync_status = 'pending'";

  static Stream<int> _pendingCount(AppDatabase db) => db
      .customSelect(
        <String>[
          _spacesPending,
          for (final String table in SyncWorker.records) _pendingIn(table),
        ].join(' UNION ALL '),
        readsFrom: <ResultSetImplementation<dynamic, dynamic>>{
          db.spaces,
          db.categories,
          db.budgetPeriods,
          db.incomeRecurrenceRules,
          db.incomes,
          db.payments,
        },
      )
      .watch()
      .map(
        (List<QueryRow> rows) =>
            rows.fold<int>(0, (int sum, QueryRow r) => sum + r.read<int>('n')),
      );
}

final NotifierProvider<SyncController, SyncState> syncProvider =
    NotifierProvider<SyncController, SyncState>(SyncController.new);
