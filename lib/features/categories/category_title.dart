import 'package:easy_localization/easy_localization.dart';
import 'package:sielto/core/db/app_database.dart';

extension CategoryTitle on Category {
  /// Starter categories in the reader's language; others as named.
  String get shownTitle {
    final String? key = starterKey;
    if (key == null) return title;
    final String path = 'starterCategory.$key';
    final String translated = tr(path);
    // No translation: the stored title.
    return translated == path ? title : translated;
  }
}
