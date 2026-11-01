import 'package:flutter_test/flutter_test.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:sielto/core/update/update_service.dart';

Map<String, Object?> release(
  String tag, {
  bool pre = false,
  bool draft = false,
  List<String> assets = const <String>[],
}) => <String, Object?>{
  'tag_name': tag,
  'prerelease': pre,
  'draft': draft,
  'body': 'Notes for $tag',
  'html_url': 'https://github.com/$repository/releases/tag/$tag',
  'assets': <Map<String, Object?>>[
    for (final String name in assets)
      <String, Object?>{
        'name': name,
        'browser_download_url': 'https://example.com/$name',
      },
  ],
};

void main() {
  final List<Map<String, Object?>> releases = <Map<String, Object?>>[
    release('v1.0.0', assets: <String>['sielto-app-1.0.0+9.zip']),
    release('v1.2.0-rc.1', pre: true),
    release('v1.1.0', assets: <String>['a.zip', 'sielto-app-1.1.0+12.apk']),
    release('v2.0.0', draft: true),
    release('nightly'),
  ];

  test('newestOf skips drafts, odd tags and, for a release build, '
      'pre-releases', () {
    final Release? newest = newestOf(releases, preReleases: false);
    expect(newest?.version, Version.parse('1.1.0'));
    expect(
      newest?.apk,
      Uri.parse('https://example.com/sielto-app-1.1.0+12.apk'),
    );
    expect(newest?.notes, 'Notes for v1.1.0');
  });

  test('a pre-release build sees pre-releases', () {
    expect(
      newestOf(releases, preReleases: true)?.version,
      Version.parse('1.2.0-rc.1'),
    );
    expect(newestOf(<Map<String, Object?>>[], preReleases: true), isNull);
  });

  test('availableUpdate only offers a newer version', () {
    final Release? newest = newestOf(releases, preReleases: false);
    expect(availableUpdate(Version.parse('1.0.0'), newest), newest);
    expect(availableUpdate(Version.parse('1.1.0'), newest), isNull);
    expect(availableUpdate(Version.parse('1.1.0-rc.2'), newest), newest);
    expect(availableUpdate(Version.parse('1.0.0'), null), isNull);
  });

  test('checkDue waits a day after the last check', () {
    final DateTime last = DateTime.utc(2026, 11, 1, 9);
    expect(checkDue(null, last), isTrue);
    expect(checkDue(last, last.add(const Duration(hours: 23))), isFalse);
    expect(checkDue(last, last.add(const Duration(hours: 24))), isTrue);
  });
}
