import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

abstract final class SupabaseProject {
  static const String url = String.fromEnvironment(
    'SIELTO_SUPABASE_URL',
    defaultValue: 'https://grjeenoqnwjaqjfjkdbg.supabase.co',
  );
  static const String publishableKey = String.fromEnvironment(
    'SIELTO_SUPABASE_KEY',
    defaultValue: 'sb_publishable_TnERZA4_o4-cfGWsvkN2lw_yda6PLid',
  );

  static SupabaseClient client() => SupabaseClient(
    url,
    publishableKey,
    authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
  );
}

enum CloudAccess {
  ready,

  /// The session is gone or this user id is bound elsewhere; only a device
  /// link from another device restores access.
  unlinked,
}

/// Binds this device's anonymous sign-in to the local user id and keeps the
/// session in the encrypted database.
class CloudIdentity {
  CloudIdentity({
    required this.db,
    required this.client,
    required this.userId,
    this.deviceName,
  }) {
    _saving = client.auth.onAuthStateChange.listen(
      (AuthState state) => unawaited(_store(state.session)),
    );
  }

  final AppDatabase db;
  final SupabaseClient client;
  final String userId;
  final Future<String?>? deviceName;
  late final StreamSubscription<AuthState> _saving;

  /// Network failures propagate; call again later.
  Future<CloudAccess> ensure() async {
    CloudIdentityData row = await _row();

    if (row.session != null && client.auth.currentSession == null) {
      try {
        await client.auth.recoverSession(row.session!);
      } on AuthRetryableFetchException {
        rethrow;
      } on AuthException catch (e) {
        if (!_revoked.contains(e.statusCode)) rethrow;
        row = row.copyWith(session: const Value<String?>(null));
        await db.update(db.cloudIdentity).replace(row);
      }
    }

    if (client.auth.currentSession == null) {
      if (row.registered) return CloudAccess.unlinked;
      await _store((await client.auth.signInAnonymously()).session);
    }

    if (!row.registered) {
      try {
        await client.rpc<void>(
          'register_new_user',
          params: <String, String?>{
            'p_user_id': userId,
            'p_device_id': row.deviceId,
            'p_display_name': await deviceName,
          },
        );
      } on PostgrestException catch (e) {
        if (e.message == 'user_id_taken') return CloudAccess.unlinked;
        rethrow;
      }
      await db
          .update(db.cloudIdentity)
          .write(const CloudIdentityCompanion(registered: Value<bool>(true)));
    }
    return CloudAccess.ready;
  }

  /// Claims [code] for this device; false for a wrong or spent code. The
  /// session is kept for another try.
  Future<bool> claim(String code, String ephemeralPublicKey) async {
    final CloudIdentityData row = await _row();
    if (client.auth.currentSession == null) {
      await _store((await client.auth.signInAnonymously()).session);
    }
    return await client.rpc<bool?>(
          'link_device_by_code',
          params: <String, String?>{
            'p_code': code.trim(),
            'p_device_id': row.deviceId,
            'p_ephemeral_pubkey': ephemeralPublicKey,
            'p_display_name': await deviceName,
          },
        ) ??
        false;
  }

  /// The owner allowed the claim: this device belongs to the account now.
  Future<void> joined() => db
      .update(db.cloudIdentity)
      .write(const CloudIdentityCompanion(registered: Value<bool>(true)));

  /// This device's id on the server.
  Future<String> deviceId() async => (await _row()).deviceId;

  /// Forgets the session and the device id, so the next cloud use is fresh.
  Future<void> forget() async {
    await db.delete(db.cloudIdentity).go();
    await client.auth.signOut(scope: SignOutScope.local);
  }

  Future<void> dispose() => _saving.cancel();

  /// Status codes of a deleted or revoked session.
  static const Set<String?> _revoked = <String?>{'400', '401', '403', '404'};

  Future<CloudIdentityData> _row() async {
    final CloudIdentityData? row = await db
        .select(db.cloudIdentity)
        .getSingleOrNull();
    if (row != null) return row;
    final CloudIdentityData fresh = CloudIdentityData(
      deviceId: const Uuid().v4(),
      registered: false,
    );
    await db.into(db.cloudIdentity).insert(fresh);
    return fresh;
  }

  Future<void> _store(Session? session) async {
    if (session == null) return;
    await db
        .update(db.cloudIdentity)
        .write(
          CloudIdentityCompanion(
            session: Value<String?>(jsonEncode(session.toJson())),
          ),
        );
  }
}
