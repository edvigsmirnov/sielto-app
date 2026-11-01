import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';

const String repository = 'edvigsmirnov/sielto-app';

typedef Release = ({Version version, String notes, Uri page, Uri? apk});

/// Releases from GitHub. Nothing else reaches the network for updates.
class UpdateService {
  UpdateService(this._client);

  final http.Client _client;

  static const Duration interval = Duration(hours: 24);

  /// The highest release; pre-releases only for a pre-release build.
  Future<Release?> newest({required bool preReleases}) async {
    final http.Response response = await _client.get(
      Uri.https(
        'api.github.com',
        '/repos/$repository/releases',
        <String, String>{'per_page': '20'},
      ),
      headers: <String, String>{'Accept': 'application/vnd.github+json'},
    );
    if (response.statusCode != 200) {
      throw HttpException('releases: ${response.statusCode}');
    }
    return newestOf(
      (jsonDecode(response.body) as List<Object?>).cast<Map<String, Object?>>(),
      preReleases: preReleases,
    );
  }

  /// Writes [url] to [into], reporting the share done.
  Future<void> download(
    Uri url,
    File into,
    void Function(double done) progress,
  ) async {
    final http.StreamedResponse response = await _client.send(
      http.Request('GET', url),
    );
    if (response.statusCode != 200) {
      throw HttpException('download: ${response.statusCode}');
    }
    final int? total = response.contentLength;
    int received = 0;
    await into.parent.create(recursive: true);
    final IOSink sink = into.openWrite();
    try {
      await for (final List<int> chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total != null && total > 0) progress(received / total);
      }
    } finally {
      await sink.close();
    }
  }
}

/// Drafts and unparsable tags are skipped.
Release? newestOf(
  List<Map<String, Object?>> releases, {
  required bool preReleases,
}) {
  Release? best;
  for (final Map<String, Object?> r in releases) {
    if (r['draft'] == true) continue;
    if (r['prerelease'] == true && !preReleases) continue;
    final Version version;
    try {
      version = Version.parse(
        (r['tag_name']! as String).replaceFirst(RegExp('^v'), ''),
      );
    } on FormatException {
      continue;
    }
    if (best != null && version <= best.version) continue;
    final Map<String, Object?>? apk =
        (r['assets'] as List<Object?>? ?? <Object?>[])
            .cast<Map<String, Object?>>()
            .where(
              (Map<String, Object?> a) =>
                  (a['name']! as String).endsWith('.apk'),
            )
            .firstOrNull;
    best = (
      version: version,
      notes: r['body'] as String? ?? '',
      page: Uri.parse(r['html_url']! as String),
      apk: apk == null
          ? null
          : Uri.parse(apk['browser_download_url']! as String),
    );
  }
  return best;
}

/// [latest] when it is ahead of the running [current] build.
Release? availableUpdate(Version current, Release? latest) =>
    latest != null && latest.version > current ? latest : null;

bool checkDue(DateTime? last, DateTime now) =>
    last == null || now.difference(last) >= UpdateService.interval;
