import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/core/db/app_database.dart';

import 'generated_migrations/schema.dart';

/// Regenerate snapshots after a schema change: `drift_dev schema dump`, then
/// `drift_dev schema generate`.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('the shipped schema matches its snapshot', () async {
    final InitializedSchema schema = await verifier.schemaAt(
      AppDatabase.currentSchemaVersion,
    );
    final AppDatabase db = AppDatabase(schema.newConnection());
    addTearDown(db.close);

    await verifier.migrateAndValidate(
      db,
      AppDatabase.currentSchemaVersion,
      // Also fails on unknown tables, views or triggers.
      options: const ValidationOptions(validateDropped: true),
    );
  });

  test('every prior version migrates forward', () async {
    for (int from = 1; from < AppDatabase.currentSchemaVersion; from++) {
      final InitializedSchema schema = await verifier.schemaAt(from);
      final AppDatabase db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, AppDatabase.currentSchemaVersion);
      await db.close();
    }
  });

  test('upgrading from v1 creates the indexes v2 added', () async {
    // Snapshots carry no indexes, so this checks it directly.
    final InitializedSchema schema = await verifier.schemaAt(1);
    final AppDatabase db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, AppDatabase.currentSchemaVersion);

    final List<QueryRow> rows = await db
        .customSelect("SELECT name FROM sqlite_schema WHERE type = 'index'")
        .get();
    expect(
      rows.map((QueryRow r) => r.read<String>('name')).toSet(),
      containsAll(<String>[
        'payments_space_title',
        'payments_space_category_due_date',
      ]),
    );
  });

  test('upgrading to v3 keys the starter categories v2 wrote', () async {
    // v2 starter titles get keys; user-named categories do not.
    final InitializedSchema schema = await verifier.schemaAt(2);
    schema.rawDatabase
      ..execute(
        'INSERT INTO spaces (id, title, space_type, budget_mode, owner_id, '
        'storage_mode, timezone, currency_code, created_at) VALUES '
        "('s', 'S', 'personal', 'flow', 'u', 'local', 'UTC', 'EUR', 0)",
      )
      ..execute(
        'INSERT INTO categories (id, space_id, title, created_at, '
        "client_edited_at) VALUES ('a', 's', 'Аренда', 0, 0), "
        "('b', 's', 'Groceries', 0, 0)",
      );
    final AppDatabase db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, AppDatabase.currentSchemaVersion);

    final List<QueryRow> rows = await db
        .customSelect('SELECT starter_key FROM categories ORDER BY id')
        .get();
    expect(
      <String?>[
        for (final QueryRow r in rows) r.readNullable<String>('starter_key'),
      ],
      <String?>['rent', null],
    );
  });

  test(
    'upgrading to v4 suffixes titles that differ in Cyrillic case',
    () async {
      final InitializedSchema schema = await verifier.schemaAt(3);
      registerSqlFunctions(schema.rawDatabase);
      schema.rawDatabase
        ..execute(
          'INSERT INTO spaces (id, title, space_type, budget_mode, owner_id, '
          'storage_mode, timezone, currency_code, created_at) VALUES '
          "('s', 'S', 'personal', 'flow', 'u', 'local', 'UTC', 'EUR', 0)",
        )
        ..execute(
          'INSERT INTO categories (id, space_id, title, created_at, '
          "client_edited_at) VALUES ('a', 's', 'Еда', 0, 0), "
          "('b', 's', 'еда', 1, 0)",
        );
      final AppDatabase db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, AppDatabase.currentSchemaVersion);

      final List<QueryRow> rows = await db
          .customSelect('SELECT title FROM categories ORDER BY id')
          .get();
      expect(
        <String>[for (final QueryRow r in rows) r.read<String>('title')],
        <String>['Еда', 'еда (2)'],
      );
    },
  );

  test('a fresh database reports the current user_version', () async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    final QueryRow row = await db
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(row.read<int>('user_version'), AppDatabase.currentSchemaVersion);
  });
}
