import 'package:drift/drift.dart';
import 'package:sielto/core/backup/backup_file.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/space_repository.dart';
import 'package:sielto/core/time/space_clock.dart';
import 'package:uuid/uuid.dart';

enum RestoreChoice { replace, copy, skip }

/// A decrypted backup.
class BackupContents {
  /// Throws [BackupFileException] for a schema newer than this build.
  BackupContents(this.json) {
    if ((json['schema_version']! as int) > AppDatabase.currentSchemaVersion) {
      throw const BackupFileException(BackupFileProblem.tooNew);
    }
  }

  final Map<String, Object?> json;

  DateTime get createdAt => DateTime.parse(json['created_at']! as String);

  String get userId => json['user_id']! as String;

  List<Map<String, Object?>> rows(String table) =>
      ((json['tables']! as Map<String, Object?>)[table] as List<Object?>? ??
              const <Object?>[])
          .cast<Map<String, Object?>>();

  List<({String id, String title})> get spaces => <({String id, String title})>[
    for (final Map<String, Object?> row in rows('spaces'))
      (id: row['id']! as String, title: row['title']! as String),
  ];
}

/// Every Space-owned table, parents first.
const List<String> _spaceTables = <String>[
  'spaces',
  'space_members',
  'member_local_labels',
  'categories',
  'budget_periods',
  'income_recurrence_rules',
  'incomes',
  'payments',
];

const String _deviceTable = 'custom_non_working_days';

String _defaultCopyTitle(String title) => '$title (copy)';

/// Raw rows in and out, so a backup survives schema additions.
class BackupService {
  BackupService({required this.db, required this.clock, required this.userId});

  final AppDatabase db;
  final SpaceClock clock;
  final String userId;

  /// Every Space when [spaceId] is null.
  Future<Map<String, Object?>> export({String? spaceId}) async {
    final Map<String, Object?> tables = <String, Object?>{};
    for (final String table in _spaceTables) {
      final String column = table == 'spaces' ? 'id' : 'space_id';
      tables[table] = await _select(
        'SELECT * FROM $table'
        '${spaceId == null ? '' : ' WHERE $column = ?'}',
        <Object>[?spaceId],
      );
    }
    tables[_deviceTable] = await _select('SELECT * FROM $_deviceTable');
    return <String, Object?>{
      'schema_version': AppDatabase.currentSchemaVersion,
      'created_at': clock.nowUtc().toIso8601String(),
      'user_id': userId,
      'tables': tables,
    };
  }

  /// Space ids in [backup] that already exist here.
  Future<Set<String>> conflicts(BackupContents backup) async {
    final Set<String> local = (await db.select(db.spaces).get())
        .map((Space s) => s.id)
        .toSet();
    return backup.spaces
        .map((({String id, String title}) s) => s.id)
        .where(local.contains)
        .toSet();
  }

  /// A conflicting Space missing from [choices] is skipped. Never merges.
  /// [copyTitle] names a Space imported as a copy.
  Future<void> restore(
    BackupContents backup,
    Map<String, RestoreChoice> choices, {
    String Function(String title) copyTitle = _defaultCopyTitle,
  }) async {
    final Set<String> existing = await conflicts(backup);
    await db.transaction(() async {
      for (final ({String id, String title}) space in backup.spaces) {
        final RestoreChoice? choice = existing.contains(space.id)
            ? choices[space.id] ?? RestoreChoice.skip
            : null;
        if (choice == RestoreChoice.skip) continue;
        if (choice == RestoreChoice.replace) {
          await SpaceRepository(db: db, clock: clock).deleteForever(space.id);
        }
        await _insertSpace(
          backup,
          space.id,
          copyTitle: choice == RestoreChoice.copy ? copyTitle : null,
        );
      }
      for (final Map<String, Object?> row in backup.rows(_deviceTable)) {
        await _insert(_deviceTable, row, orIgnore: true);
      }
    });
  }

  Future<void> _insertSpace(
    BackupContents backup,
    String spaceId, {
    required String Function(String title)? copyTitle,
  }) async {
    bool owned(String table, Map<String, Object?> row) =>
        (table == 'spaces' ? row['id'] : row['space_id']) == spaceId;

    // Ids are UUIDs, so any column holding one is rewritten.
    final Map<String, String> ids = <String, String>{backup.userId: userId};
    if (copyTitle != null) {
      for (final String table in _spaceTables) {
        for (final Map<String, Object?> row in backup.rows(table)) {
          final Object? id = row['id'];
          if (owned(table, row) && id is String) ids[id] = const Uuid().v4();
        }
      }
    }

    for (final String table in _spaceTables) {
      for (final Map<String, Object?> row in backup.rows(table)) {
        if (!owned(table, row)) continue;
        final Map<String, Object?> mapped = row.map(
          (String k, Object? v) =>
              MapEntry<String, Object?>(k, v is String ? ids[v] ?? v : v),
        );
        if (table == 'spaces' && copyTitle != null) {
          mapped['title'] = copyTitle(mapped['title']! as String);
        }
        if (table == 'spaces' && mapped['storage_mode'] == 'cloud') {
          mapped['storage_mode'] = 'local';
          mapped['is_archived'] = 1;
        }
        await _insert(table, mapped);
      }
    }
  }

  Future<List<Map<String, Object?>>> _select(
    String sql, [
    List<Object> args = const <Object>[],
  ]) async => <Map<String, Object?>>[
    for (final QueryRow row
        in await db
            .customSelect(
              sql,
              variables: <Variable<Object>>[
                for (final Object a in args) Variable<Object>(a),
              ],
            )
            .get())
      row.data,
  ];

  static final RegExp _columnName = RegExp(r'^[a-z_]+$');

  Future<void> _insert(
    String table,
    Map<String, Object?> row, {
    bool orIgnore = false,
  }) {
    if (!row.keys.every(_columnName.hasMatch)) {
      throw const BackupFileException(BackupFileProblem.notABackup);
    }
    return db.customInsert(
      'INSERT ${orIgnore ? 'OR IGNORE ' : ''}INTO $table '
      '(${row.keys.join(', ')}) '
      'VALUES (${List<String>.filled(row.length, '?').join(', ')})',
      variables: <Variable<Object>>[
        for (final Object? v in row.values) Variable<Object>(v),
      ],
      updates: db.allTables.toSet(),
    );
  }
}
