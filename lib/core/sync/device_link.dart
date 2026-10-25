import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:supabase/supabase.dart';

/// Hands the Recovery Key to a device the owner allowed; the server sees only
/// ciphertext. Layout: sender public key (32) | nonce (12) | ciphertext | MAC.
abstract final class DeviceLink {
  static final X25519 _exchange = X25519();
  static final AesGcm _cipher = AesGcm.with256bits();
  static const Duration _poll = Duration(seconds: 2);

  static Future<SimpleKeyPair> newKeyPair() => _exchange.newKeyPair();

  static Future<String> publicKeyOf(SimpleKeyPair pair) async =>
      base64Encode((await pair.extractPublicKey()).bytes);

  static Future<String> seal(String secret, String recipientPublicKey) async {
    final SimpleKeyPair sender = await _exchange.newKeyPair();
    final List<int> senderPublic = (await sender.extractPublicKey()).bytes;
    final List<int> recipient = base64Decode(recipientPublicKey);
    final SecretBox box = await _cipher.encrypt(
      utf8.encode(secret),
      secretKey: await _key(sender, recipient, senderPublic, recipient),
    );
    return base64Encode(<int>[
      ...senderPublic,
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  /// Throws [SecretBoxAuthenticationError] on a wrong key or tampering.
  static Future<String> open(String sealed, SimpleKeyPair recipient) async {
    final List<int> bytes = base64Decode(sealed);
    final List<int> senderPublic = bytes.sublist(0, 32);
    final List<int> clear = await _cipher.decrypt(
      SecretBox(
        bytes.sublist(44, bytes.length - 16),
        nonce: bytes.sublist(32, 44),
        mac: Mac(bytes.sublist(bytes.length - 16)),
      ),
      secretKey: await _key(
        recipient,
        senderPublic,
        senderPublic,
        (await recipient.extractPublicKey()).bytes,
      ),
    );
    return utf8.decode(clear);
  }

  static Future<SecretKey> _key(
    SimpleKeyPair mine,
    List<int> theirs,
    List<int> senderPublic,
    List<int> recipientPublic,
  ) async => Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
    secretKey: await _exchange.sharedSecretKey(
      keyPair: mine,
      remotePublicKey: SimplePublicKey(theirs, type: KeyPairType.x25519),
    ),
    nonce: <int>[...senderPublic, ...recipientPublic],
    info: utf8.encode('sielto recovery key handover'),
  );

  /// On the device that made the code: the claim, once one comes; null when
  /// nobody claims it in time.
  static Future<LinkClaim?> waitForClaim(
    SupabaseClient client, {
    Duration timeout = const Duration(minutes: 5),
    bool Function()? keepGoing,
  }) async {
    final DateTime until = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(until) && (keepGoing?.call() ?? true)) {
      final Map<String, dynamic>? row = await client
          .from('device_link_codes')
          .select('id, ephemeral_pubkey, claimant_name')
          .eq('status', 'claimed')
          .eq('owner_auth_uid', client.auth.currentUser!.id)
          .maybeSingle();
      if (row != null) {
        return (
          id: row['id'] as String,
          publicKey: row['ephemeral_pubkey'] as String,
          name: row['claimant_name'] as String?,
        );
      }
      await Future<void>.delayed(_poll);
    }
    return null;
  }

  /// Allows or refuses [claim]; allowing seals [recoveryKey] to it. False when
  /// the answer came too late.
  static Future<bool> answer(
    SupabaseClient client,
    LinkClaim claim, {
    required bool allow,
    String? recoveryKey,
  }) async => await client.rpc<bool>(
    'answer_device_link',
    params: <String, Object?>{
      'p_link': claim.id,
      'p_allow': allow,
      'p_payload': allow && recoveryKey != null
          ? await seal(recoveryKey, claim.publicKey)
          : null,
    },
  );

  /// On the new device: the owner's answer; null when none comes in time.
  static Future<LinkAnswer?> awaitAnswer(
    SupabaseClient client,
    SimpleKeyPair keyPair, {
    Duration timeout = const Duration(minutes: 5),
    bool Function()? keepGoing,
  }) async {
    final DateTime until = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(until) && (keepGoing?.call() ?? true)) {
      final List<dynamic> rows = await client.rpc<List<dynamic>>(
        'device_link_claim',
      );
      final Map<String, dynamic>? row =
          rows.firstOrNull as Map<String, dynamic>?;
      switch (row?['status']) {
        case 'allowed':
          final String? sealed = row!['encrypted_payload'] as String?;
          return (
            allowed: true,
            userId: row['user_id'] as String,
            recoveryKey: sealed == null ? null : await open(sealed, keyPair),
          );
        case 'refused':
          return (allowed: false, userId: null, recoveryKey: null);
      }
      await Future<void>.delayed(_poll);
    }
    return null;
  }
}

/// A claimed code, as the owner's device sees it.
typedef LinkClaim = ({String id, String publicKey, String? name});

/// The owner's answer, as the new device sees it.
typedef LinkAnswer = ({bool allowed, String? userId, String? recoveryKey});
