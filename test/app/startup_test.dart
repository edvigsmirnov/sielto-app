import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sielto/app/startup.dart';
import 'package:sielto/core/db/app_database.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('startup_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a database without its envelope is not a first run', () {
    expect(StartupNeedsPassphrase(dir).firstRun, isTrue);
    File(p.join(dir.path, databaseFileName)).writeAsBytesSync(<int>[0]);
    expect(StartupNeedsPassphrase(dir).firstRun, isFalse);
  });
}
