import 'dart:io';

// decimal, calendar_date and enums are used by app_database.g.dart.
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sielto/core/crypto/database_key.dart';
import 'package:sielto/core/db/converters.dart';
import 'package:sielto/core/db/tables.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sqlite3/sqlite3.dart';

part 'app_database.g.dart';

/// The local database, the source of truth.
@DriftDatabase(
  tables: <Type>[
    Spaces,
    SpaceMembers,
    MemberLocalLabels,
    UserProfiles,
    Categories,
    BudgetPeriods,
    IncomeRecurrenceRules,
    Incomes,
    Payments,
    HolidayCache,
    CustomNonWorkingDays,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Bump with a new [migration] step and a new schema snapshot.
  static const int currentSchemaVersion = 4;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _createIndexes(this);
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        // v2: title autocomplete index only.
        await _createIndexes(m.database);
      }
      if (from < 3) {
        await m.addColumn(categories, categories.starterKey);
        for (final MapEntry<String, List<String>> e
            in _v2StarterTitles.entries) {
          for (final String title in e.value) {
            await customUpdate(
              'UPDATE categories SET starter_key = ? '
              'WHERE starter_key IS NULL AND title = ?',
              variables: <Variable<Object>>[
                Variable<String>(e.key),
                Variable<String>(title),
              ],
              updates: <TableInfo<Table, Object?>>{categories},
            );
          }
        }
      }
      if (from < 4) {
        // v4: `lower` folds Unicode; rebuild the indexes that use it.
        await _renameCaseVariantCategories(this);
        await customStatement(
          'DROP INDEX IF EXISTS categories_unique_active_title',
        );
        await customStatement('DROP INDEX IF EXISTS payments_space_title');
        await _createIndexes(this);
      }
    },
    beforeOpen: (OpeningDetails details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

/// SQLite's own `lower` folds ASCII only. Register on every connection before
/// the first query, or the Unicode-keyed indexes disagree with lookups.
void registerSqlFunctions(Database raw) => raw.createFunction(
  functionName: 'lower',
  argumentCount: const AllowedArgumentCount(1),
  deterministic: true,
  directOnly: false,
  function: (List<Object?> args) {
    final Object? value = args.first;
    return value is String ? value.toLowerCase() : value;
  },
);

/// Active titles that differed only in non-ASCII case were distinct before v4.
/// Suffix all but the first, or the unique index rebuild fails.
Future<void> _renameCaseVariantCategories(AppDatabase db) async {
  final List<QueryRow> rows = await db
      .customSelect(
        'SELECT id, space_id, title FROM categories '
        'WHERE is_deleted = 0 ORDER BY created_at, id',
      )
      .get();
  final Set<String> taken = <String>{
    for (final QueryRow r in rows)
      '${r.read<String>('space_id')}/${r.read<String>('title').toLowerCase()}',
  };
  final Set<String> seen = <String>{};
  for (final QueryRow r in rows) {
    final String space = r.read<String>('space_id');
    final String title = r.read<String>('title');
    if (seen.add('$space/${title.toLowerCase()}')) continue;
    int n = 2;
    while (taken.contains('$space/${'$title ($n)'.toLowerCase()}')) {
      n++;
    }
    taken.add('$space/${'$title ($n)'.toLowerCase()}');
    await db.customUpdate(
      'UPDATE categories SET title = ?, starter_key = NULL WHERE id = ?',
      variables: <Variable<Object>>[
        Variable<String>('$title ($n)'),
        Variable<String>(r.read<String>('id')),
      ],
      updates: <TableInfo<Table, Object?>>{db.categories},
    );
  }
}

/// Starter category titles written by v2, per key. Frozen: do not edit.
const Map<String, List<String>> _v2StarterTitles = <String, List<String>>{
  'rent': <String>['Rent', 'Аренда'],
  'loans': <String>['Loans', 'Кредиты'],
  'utilities': <String>['Utilities', 'Коммуналка'],
  'internet': <String>['Internet', 'Интернет'],
  'flexible': <String>['Flexible spending', 'Гибкие расходы'],
};

/// Partial and expression indexes. All `IF NOT EXISTS`.
Future<void> _createIndexes(DatabaseConnectionUser db) async {
  // Titles are unique among active categories only.
  await db.customStatement(
    'CREATE UNIQUE INDEX IF NOT EXISTS categories_unique_active_title '
    'ON categories (space_id, lower(title)) WHERE is_deleted = 0',
  );

  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS payments_space_due_date '
    'ON payments (space_id, due_date) WHERE is_deleted = 0',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS incomes_space_expected_date '
    'ON incomes (space_id, expected_date) WHERE is_deleted = 0',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS budget_periods_space_start '
    'ON budget_periods (space_id, start_date) WHERE is_deleted = 0',
  );

  // Title autocomplete and Analytics grouping use the same key.
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS payments_space_title '
    'ON payments (space_id, lower(trim(title))) WHERE is_deleted = 0',
  );

  // Analytics by category and range.
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS payments_space_category_due_date '
    'ON payments (space_id, category_id, due_date) WHERE is_deleted = 0',
  );

  for (final String table in <String>[
    'payments',
    'incomes',
    'categories',
    'income_recurrence_rules',
    'budget_periods',
  ]) {
    await db.customStatement(
      'CREATE INDEX IF NOT EXISTS ${table}_pending_sync '
      "ON $table (space_id) WHERE sync_status = 'pending'",
    );
  }
}

const String databaseFileName = 'sielto.sqlite';

/// `PRAGMA key` must be the first statement; the read after it fails fast on
/// a wrong key.
QueryExecutor openEncryptedDatabase({
  required Directory directory,
  required DatabaseKey key,
  String fileName = databaseFileName,
}) {
  final File file = File(p.join(directory.path, fileName));
  directory.createSync(recursive: true);

  return NativeDatabase.createInBackground(
    file,
    setup: (Database raw) {
      raw.execute('PRAGMA key = ${key.toPragmaLiteral()}');
      raw.execute('SELECT count(*) FROM sqlite_schema');
      registerSqlFunctions(raw);
    },
  );
}
