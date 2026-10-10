import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:supabase/supabase.dart';

/// Hands the Recovery Key to a newly linked device; the server sees only
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

  /// On the device that made the code: waits for the new device to claim it,
  /// then seals [recoveryKey] to it. False when nobody claimed it in time.
  static Future<bool> handOver(
    SupabaseClient client,
    String recoveryKey, {
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final DateTime until = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(until)) {
      final Map<String, dynamic>? claimed = await client
          .from('device_link_codes')
          .select('id, ephemeral_pubkey')
          .not('linked_auth_uid', 'is', null)
          .isFilter('encrypted_payload', null)
          .eq('owner_auth_uid', client.auth.currentUser!.id)
          .maybeSingle();
      if (claimed != null) {
        await client
            .from('device_link_codes')
            .update(<String, String>{
              'encrypted_payload': await seal(
                recoveryKey,
                claimed['ephemeral_pubkey'] as String,
              ),
            })
            .eq('id', claimed['id'] as String);
        return true;
      }
      await Future<void>.delayed(_poll);
    }
    return false;
  }

  /// On the new device: null when the other device did not answer in time.
  static Future<String?> receive(
    SupabaseClient client,
    SimpleKeyPair keyPair, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final DateTime until = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(until)) {
      final Map<String, dynamic>? row = await client
          .from('device_link_codes')
          .select('encrypted_payload')
          .eq('linked_auth_uid', client.auth.currentUser!.id)
          .not('encrypted_payload', 'is', null)
          .maybeSingle();
      if (row != null) {
        return open(row['encrypted_payload'] as String, keyPair);
      }
      await Future<void>.delayed(_poll);
    }
    return null;
  }
}
