import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every literal `tr()` and `plural()` key exists in the dictionaries.
void main() {
  test('every key used in lib exists in en.json', () {
    final Map<String, dynamic> dictionary = jsonDecode(
      File('assets/translations/en.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    bool has(String key) {
      Object? node = dictionary;
      for (final String part in key.split('.')) {
        if (node is! Map<String, dynamic>) return false;
        node = node[part];
        if (node == null) return false;
      }
      return true;
    }

    // Interpolated keys cannot be checked statically.
    final RegExp call = RegExp(r"""(?:tr|plural)\(\s*'([a-zA-Z0-9_.]+)'""");

    final List<String> missing = <String>[];
    for (final FileSystemEntity entity in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final String source = entity.readAsStringSync();
      for (final RegExpMatch match in call.allMatches(source)) {
        final String key = match.group(1)!;
        if (!has(key)) missing.add('$key  (${entity.path})');
      }
    }

    expect(
      missing,
      isEmpty,
      reason:
          'these keys are used in lib but absent from en.json, so they render '
          'as raw keys:\n${missing.join('\n')}',
    );
  });
}
