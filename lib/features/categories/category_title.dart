import 'package:easy_localization/easy_localization.dart';
import 'package:sielto/core/db/app_database.dart';

extension CategoryTitle on Category {
  /// The title to show: a starter category in the reader's language, a
  /// category the user named exactly as named (spec 7).
  String get shownTitle {
    final String? key = starterKey;
    if (key == null) return title;
    final String path = 'starterCategory.$key';
    final String translated = tr(path);
    // A key this build has no text for shows the stored title.
    return translated == path ? title : translated;
  }
}
