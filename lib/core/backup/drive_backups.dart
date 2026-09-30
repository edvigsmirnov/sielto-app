import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sielto/core/backup/backup_file.dart';

class DriveSnapshot {
  const DriveSnapshot({
    required this.id,
    required this.createdAt,
    required this.size,
  });

  final String id;
  final DateTime createdAt;
  final int size;
}

class DriveException implements Exception {
  const DriveException(this.status);

  final int status;

  @override
  String toString() => 'DriveException: HTTP $status';
}

/// Snapshots in Drive's hidden app folder, newest first.
class DriveBackups {
  const DriveBackups(this.client);

  static const String scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const int keep = 7;

  static const String _api = 'https://www.googleapis.com/drive/v3';

  /// Authorized for [scope].
  final http.Client client;

  Future<String?> accountEmail() async {
    final Map<String, Object?> about = await _json(
      await client.get(Uri.parse('$_api/about?fields=user(emailAddress)')),
    );
    return (about['user'] as Map<String, Object?>?)?['emailAddress'] as String?;
  }

  Future<List<DriveSnapshot>> list() async {
    final Map<String, Object?> body = await _json(
      await client.get(
        Uri.parse('$_api/files').replace(
          queryParameters: <String, String>{
            'spaces': 'appDataFolder',
            'fields': 'files(id,createdTime,size)',
            'orderBy': 'createdTime desc',
            'pageSize': '100',
          },
        ),
      ),
    );
    return <DriveSnapshot>[
      for (final Map<String, Object?> f
          in (body['files']! as List<Object?>).cast<Map<String, Object?>>())
        DriveSnapshot(
          id: f['id']! as String,
          createdAt: DateTime.parse(f['createdTime']! as String),
          size: int.tryParse(f['size'] as String? ?? '') ?? 0,
        ),
    ];
  }

  Future<Uint8List> download(String id) async {
    final http.Response response = await client.get(
      Uri.parse('$_api/files/$id?alt=media'),
    );
    _check(response);
    return response.bodyBytes;
  }

  /// Uploads [bytes], then deletes all but the newest [keep].
  Future<void> upload(Uint8List bytes, DateTime now) async {
    const String boundary = 'sielto-backup-boundary';
    final String stamp = now.toUtc().toIso8601String().replaceAll(':', '-');
    final List<int> body = <int>[
      ...utf8.encode(
        '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '${jsonEncode(<String, Object>{
          'name': 'sielto_$stamp.${BackupFile.extension}',
          'parents': <String>['appDataFolder'],
        })}\r\n'
        '--$boundary\r\n'
        'Content-Type: application/octet-stream\r\n\r\n',
      ),
      ...bytes,
      ...utf8.encode('\r\n--$boundary--'),
    ];
    _check(
      await client.post(
        Uri.parse(
          'https://www.googleapis.com/upload/drive/v3/files'
          '?uploadType=multipart',
        ),
        headers: <String, String>{
          'Content-Type': 'multipart/related; boundary=$boundary',
        },
        body: body,
      ),
    );
    final List<DriveSnapshot> all = await list();
    for (final DriveSnapshot old in all.skip(keep)) {
      _check(await client.delete(Uri.parse('$_api/files/${old.id}')));
    }
  }

  static void _check(http.Response response) {
    if (response.statusCode >= 300) throw DriveException(response.statusCode);
  }

  static Future<Map<String, Object?>> _json(http.Response response) async {
    _check(response);
    return jsonDecode(response.body) as Map<String, Object?>;
  }
}
