import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sielto/core/backup/drive_backups.dart';

void main() {
  test('upload goes to the app folder and keeps the newest seven', () async {
    final List<String> files = <String>[for (int i = 0; i < 8; i++) 'f$i'];
    final List<String> deleted = <String>[];
    String? uploaded;

    final DriveBackups drive = DriveBackups(
      MockClient((http.Request request) async {
        final String path = request.url.path;
        if (request.method == 'POST') {
          uploaded = utf8.decode(request.bodyBytes, allowMalformed: true);
          files.insert(0, 'new');
          return http.Response('{"id":"new"}', 200);
        }
        if (request.method == 'DELETE') {
          deleted.add(path.split('/').last);
          return http.Response('', 204);
        }
        expect(request.url.queryParameters['spaces'], 'appDataFolder');
        return http.Response(
          jsonEncode(<String, Object>{
            'files': <Map<String, String>>[
              for (int i = 0; i < files.length; i++)
                <String, String>{
                  'id': files[i],
                  'createdTime': DateTime.utc(
                    2026,
                    9,
                    30 - i,
                  ).toIso8601String(),
                  'size': '1024',
                },
            ],
          }),
          200,
        );
      }),
    );

    await drive.upload(
      Uint8List.fromList(<int>[1, 2, 3]),
      DateTime.utc(2026, 9, 30),
    );

    expect(uploaded, contains('"parents":["appDataFolder"]'));
    expect(uploaded, contains('sielto_2026-09-30T00-00-00.000Z.finbackup'));
    expect(deleted, <String>['f6', 'f7']);
  });

  test('an HTTP error surfaces as DriveException', () async {
    final DriveBackups drive = DriveBackups(
      MockClient((_) async => http.Response('', 401)),
    );
    await expectLater(drive.list(), throwsA(isA<DriveException>()));
  });
}
