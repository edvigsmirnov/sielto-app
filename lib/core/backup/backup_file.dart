import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:sielto/core/crypto/kdf.dart';

/// A `.finbackup` file: `SIELTOBK` | format (1) | salt (16) | nonce (12) |
/// AES-256-GCM of gzipped JSON | MAC (16). The header is the associated data.
abstract final class BackupFile {
  static const String extension = 'finbackup';
  static const int format = 1;

  static final List<int> _magic = ascii.encode('SIELTOBK');
  static const int _nonceLength = 12;
  static const int _macLength = 16;
  static final int _headerLength = _magic.length + 1 + Kdf.saltLength;

  static final AesGcm _cipher = AesGcm.with256bits();

  static Future<Uint8List> seal(
    Map<String, Object?> contents,
    String recoveryKey,
  ) async {
    final Uint8List salt = Kdf.salt();
    final List<int> header = <int>[..._magic, format, ...salt];
    final SecretBox box = await _cipher.encrypt(
      gzip.encode(utf8.encode(jsonEncode(contents))),
      secretKey: SecretKey(await Kdf.recoveryKey(recoveryKey, salt)),
      aad: header,
    );
    return Uint8List.fromList(<int>[
      ...header,
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  /// Checks the signature without a key.
  static bool looksLikeBackup(Uint8List bytes) =>
      bytes.length > _headerLength + _nonceLength + _macLength &&
      _startsWithMagic(bytes);

  /// Throws [BackupFileException].
  static Future<Map<String, Object?>> open(
    Uint8List bytes,
    String recoveryKey,
  ) async {
    if (!looksLikeBackup(bytes)) {
      throw const BackupFileException(BackupFileProblem.notABackup);
    }
    if (bytes[_magic.length] > format) {
      throw const BackupFileException(BackupFileProblem.tooNew);
    }
    final Uint8List header = bytes.sublist(0, _headerLength);
    final Uint8List salt = header.sublist(_magic.length + 1);
    final int nonceEnd = _headerLength + _nonceLength;
    final int cipherEnd = bytes.length - _macLength;
    final List<int> clear;
    try {
      clear = await _cipher.decrypt(
        SecretBox(
          bytes.sublist(nonceEnd, cipherEnd),
          nonce: bytes.sublist(_headerLength, nonceEnd),
          mac: Mac(bytes.sublist(cipherEnd)),
        ),
        secretKey: SecretKey(await Kdf.recoveryKey(recoveryKey, salt)),
        aad: header,
      );
    } on SecretBoxAuthenticationError {
      throw const BackupFileException(BackupFileProblem.wrongKey);
    }
    return jsonDecode(utf8.decode(gzip.decode(clear))) as Map<String, Object?>;
  }

  static bool _startsWithMagic(Uint8List bytes) {
    for (int i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return false;
    }
    return true;
  }
}

enum BackupFileProblem { notABackup, tooNew, wrongKey }

class BackupFileException implements Exception {
  const BackupFileException(this.problem);

  final BackupFileProblem problem;

  @override
  String toString() => 'BackupFileException: ${problem.name}';
}
