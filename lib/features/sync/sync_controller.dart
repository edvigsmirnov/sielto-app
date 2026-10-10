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

enum JoinResult {
  joined,
  wrongCode,
  tooManyAttempts,
  spaceFull,
  offlineMode,
  noNetwork,
  unlinked,
}

typedef SyncState = ({bool unlinked, DateTime? lastSync});

typedef Member = ({String userId, String? name, bool owner, bool me});

/// What this user calls another member; visible to no one else.
typedef MemberLabel = ({String? name, String? role});

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
  String? _uploadedName;
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
        return;
      }
      if (await _worker.anyVanished()) _soon();
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
        if (_worker.vanished.isNotEmpty) {
          await ref.read(vanishedSpacesProvider.notifier).add(_worker.vanished);
        }
        await _uploadProfile();
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
    // An empty device starts over, as a fresh install.
    if ((await _db.select(_db.spaces).get()).isEmpty) {
      await ref.read(localSettingsProvider).startOver();
      ref.invalidate(userIdProvider);
    }
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

  /// Makes the name visible to people who share a Space with this user.
  Future<void> _uploadProfile() async {
    final String? name = ref.read(nameProvider)?.trim();
    if (name == null || name.isEmpty || name == _uploadedName) return;
    await _client.from('user_profiles').upsert(<String, String>{
      'user_id': ref.read(userIdProvider),
      'nickname': name,
      'client_edited_at': DateTime.now().toUtc().toIso8601String(),
    });
    _uploadedName = name;
  }

  /// A 15-minute code for joining [spaceId]; null with [full] when there is
  /// no room, or with a failure result.
  Future<({CloudResult result, String? code, bool full})> createInvite(
    String spaceId,
  ) => _serial(() async {
    final CloudResult signedIn = await _signIn();
    if (signedIn != CloudResult.done) {
      return (result: signedIn, code: null, full: false);
    }
    try {
      await _uploadProfile();
      final String code = await _client.rpc<String>(
        'create_space_invite',
        params: <String, String>{'p_space_id': spaceId},
      );
      return (result: CloudResult.done, code: code, full: false);
    } on PostgrestException catch (e) {
      return (
        result: e.message == 'space_full'
            ? CloudResult.done
            : CloudResult.noNetwork,
        code: null,
        full: e.message == 'space_full',
      );
    } on Exception {
      return (result: CloudResult.noNetwork, code: null, full: false);
    }
  });

  /// Drops the unused code before anyone joins with it.
  Future<bool> revokeInvites(String spaceId) => _online(
    () => _client.from('space_invites').delete().eq('space_id', spaceId),
  );

  /// Joins someone else's Space and brings it here. Returns its id.
  Future<({JoinResult result, String? spaceId})> joinSpace(String code) async {
    if (ref.read(offlineModeProvider)) {
      return (result: JoinResult.offlineMode, spaceId: null);
    }
    final ({JoinResult result, String? spaceId}) joined = await _serial(
      () async {
        final CloudResult signedIn = await _signIn();
        if (signedIn != CloudResult.done) {
          return (
            result: signedIn == CloudResult.unlinked
                ? JoinResult.unlinked
                : JoinResult.noNetwork,
            spaceId: null,
          );
        }
        try {
          await _uploadProfile();
          final String? spaceId = await _client.rpc<String?>(
            'join_space_by_token',
            params: <String, String>{'p_code': code.trim()},
          );
          return (
            result: spaceId == null ? JoinResult.wrongCode : JoinResult.joined,
            spaceId: spaceId,
          );
        } on PostgrestException catch (e) {
          return (
            result: switch (e.message) {
              'too_many_attempts' => JoinResult.tooManyAttempts,
              'space_full' => JoinResult.spaceFull,
              _ => JoinResult.noNetwork,
            },
            spaceId: null,
          );
        } on Exception {
          return (result: JoinResult.noNetwork, spaceId: null);
        }
      },
    );
    if (joined.result == JoinResult.joined) await syncNow();
    return joined;
  }

  /// Everyone in [spaceId], the owner first.
  Future<({CloudResult result, List<Member> members})> members(
    String spaceId,
  ) => _serial(() async {
    final CloudResult signedIn = await _signIn();
    if (signedIn != CloudResult.done) {
      return (result: signedIn, members: const <Member>[]);
    }
    try {
      final Map<String, dynamic> space = await _client
          .from('spaces')
          .select('owner_id')
          .eq('id', spaceId)
          .single();
      final List<Map<String, dynamic>> rows = await _client
          .from('space_members')
          .select('user_id')
          .eq('space_id', spaceId)
          .order('joined_at');
      final List<String> ids = <String>[
        for (final Map<String, dynamic> r in rows) r['user_id'] as String,
      ];
      final List<Map<String, dynamic>> profiles = await _client
          .from('user_profiles')
          .select('user_id, nickname')
          .inFilter('user_id', ids);
      final Map<String, String> names = <String, String>{
        for (final Map<String, dynamic> p in profiles)
          p['user_id'] as String: p['nickname'] as String,
      };
      final String me = ref.read(userIdProvider);
      final String ownerId = space['owner_id'] as String;
      final List<Member> members = <Member>[
        for (final String id in ids)
          (userId: id, name: names[id], owner: id == ownerId, me: id == me),
      ]..sort((Member a, Member b) => (b.owner ? 1 : 0) - (a.owner ? 1 : 0));
      return (result: CloudResult.done, members: members);
    } on Exception {
      return (result: CloudResult.noNetwork, members: const <Member>[]);
    }
  });

  /// This user's private labels in [spaceId], by member. Pending local edits
  /// go up first; the later edit wins.
  Future<Map<String, MemberLabel>> labels(String spaceId) => _serial(() async {
    final String me = ref.read(userIdProvider);
    if (await _signIn() == CloudResult.done) {
      try {
        final List<MemberLocalLabel> pending =
            await (_db.select(_db.memberLocalLabels)..where(
                  ($MemberLocalLabelsTable t) =>
                      t.spaceId.equals(spaceId) &
                      t.syncStatus.equalsValue(SyncStatus.pending),
                ))
                .get();
        for (final MemberLocalLabel l in pending) {
          await _client.from('member_local_labels').upsert(_labelRow(l));
        }
        final List<Map<String, dynamic>> remote = await _client
            .from('member_local_labels')
            .select()
            .eq('space_id', spaceId)
            .eq('viewer_user_id', me);
        await _db.batch((Batch b) {
          for (final Map<String, dynamic> r in remote) {
            b.insert(
              _db.memberLocalLabels,
              MemberLocalLabelsCompanion.insert(
                spaceId: spaceId,
                viewerUserId: me,
                targetUserId: r['target_user_id'] as String,
                localName: Value<String?>(r['local_name'] as String?),
                localRole: Value<String?>(r['local_role'] as String?),
                clientEditedAt: DateTime.parse(r['client_edited_at'] as String),
                syncStatus: const Value<SyncStatus>(SyncStatus.synced),
              ),
              mode: InsertMode.insertOrReplace,
            );
          }
        });
      } on Exception catch (e) {
        debugPrint('labels: $e');
      }
    }
    final List<MemberLocalLabel> rows =
        await (_db.select(_db.memberLocalLabels)..where(
              ($MemberLocalLabelsTable t) =>
                  t.spaceId.equals(spaceId) & t.viewerUserId.equals(me),
            ))
            .get();
    return <String, MemberLabel>{
      for (final MemberLocalLabel l in rows)
        l.targetUserId: (name: l.localName, role: l.localRole),
    };
  });

  /// Saved here at once; uploaded when the cloud is reachable.
  Future<void> setLabel(
    String spaceId,
    String targetUserId,
    MemberLabel label,
  ) async {
    String? clean(String? s) => s == null || s.trim().isEmpty ? null : s.trim();
    final MemberLocalLabelsCompanion row = MemberLocalLabelsCompanion.insert(
      spaceId: spaceId,
      viewerUserId: ref.read(userIdProvider),
      targetUserId: targetUserId,
      localName: Value<String?>(clean(label.name)),
      localRole: Value<String?>(clean(label.role)),
      clientEditedAt: DateTime.now().toUtc(),
      syncStatus: const Value<SyncStatus>(SyncStatus.pending),
    );
    await _db
        .into(_db.memberLocalLabels)
        .insert(row, mode: InsertMode.insertOrReplace);
    await labels(spaceId);
  }

  static Map<String, Object?> _labelRow(MemberLocalLabel l) =>
      <String, Object?>{
        'space_id': l.spaceId,
        'viewer_user_id': l.viewerUserId,
        'target_user_id': l.targetUserId,
        'local_name': l.localName,
        'local_role': l.localRole,
        'client_edited_at': l.clientEditedAt.toUtc().toIso8601String(),
      };

  Future<bool> removeMember(String spaceId, String userId) => _online(
    () => _client.rpc<void>(
      'remove_member',
      params: <String, String>{'p_space_id': spaceId, 'p_user_id': userId},
    ),
  );

  /// The new owner arrives here with the next sync.
  Future<bool> transferOwnership(String spaceId, String userId) async {
    final bool done = await _online(
      () => _client.rpc<void>(
        'transfer_ownership',
        params: <String, String>{'p_space_id': spaceId, 'p_user_id': userId},
      ),
    );
    if (done) await syncNow();
    return done;
  }

  /// Leaves someone else's Space; its copy here goes too.
  Future<bool> leaveSpace(String spaceId) => _serial(() async {
    if (await _signIn() != CloudResult.done) return false;
    try {
      await _client.rpc<void>(
        'leave_space',
        params: <String, String>{'p_space_id': spaceId},
      );
    } on Exception {
      return false;
    }
    await ref.read(repositoriesProvider).spaces.deleteForever(spaceId);
    return true;
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
