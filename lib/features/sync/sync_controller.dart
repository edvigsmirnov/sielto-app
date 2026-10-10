import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/sync/cloud_identity.dart';
import 'package:sielto/core/sync/sync_worker.dart';
import 'package:supabase/supabase.dart';

enum CloudResult { done, offlineMode, noNetwork, unlinked }

typedef SyncState = ({bool unlinked, DateTime? lastSync});

/// Syncs at start, on resume, after cloud edits and on server changes.
/// Sends nothing while fully offline or before any cloud use.
class SyncController extends Notifier<SyncState> with WidgetsBindingObserver {
  static const Duration _settle = Duration(seconds: 3);

  late SupabaseClient _client;
  late CloudIdentity _identity;
  late SyncWorker _worker;
  Future<void> _tail = Future<void>.value();
  bool _queued = false;
  Timer? _debounce;
  RealtimeChannel? _channel;

  AppDatabase get _db => ref.read(databaseProvider);

  @override
  SyncState build() {
    final AppDatabase db = ref.watch(databaseProvider);
    _client = SupabaseProject.client();
    _identity = CloudIdentity(
      db: db,
      client: _client,
      userId: ref.watch(userIdProvider),
    );
    _worker = SyncWorker(db: db, client: _client);

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
      unawaited(edits.cancel());
      _closeChannel();
      unawaited(_identity.dispose());
      _client.dispose();
    });
    Future<void>.microtask(syncNow);
    return (unlinked: false, lastSync: null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(syncNow());
  }

  /// Network trouble is left for the next run.
  Future<void> syncNow() {
    if (_queued) return _tail;
    _queued = true;
    return _serial(() async {
      _queued = false;
      if (ref.read(offlineModeProvider) || !await _usesCloud()) return;
      try {
        if (await _identity.ensure() == CloudAccess.unlinked) {
          state = (unlinked: true, lastSync: state.lastSync);
          return;
        }
        _channel ??= _worker.watchRemote(_soon);
        await _worker.syncAll();
        state = (unlinked: false, lastSync: DateTime.now());
      } on Exception catch (e) {
        debugPrint('sync: $e');
      }
    });
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
        );
        for (final String table in SyncWorker.records) {
          await _db.customUpdate(
            "UPDATE $table SET sync_status = 'pending' "
            "WHERE space_id = ? AND sync_status <> 'rejected'",
            variables: <Variable<Object>>[Variable<String>(spaceId)],
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
    await _db.customUpdate(
      "UPDATE spaces SET storage_mode = 'local', sync_status = 'none', "
      'server_received_at = NULL, synced_until = NULL WHERE id = ?',
      variables: <Variable<Object>>[Variable<String>(spaceId)],
    );
    return CloudResult.done;
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
