import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/infrastructure/persistence/local/app_database.dart';

import '../../../generated_migrations/schema.dart';

void main() {
  test(
    'v1 to v2 migration preserves player data and adds sync tables',
    () async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final schema = await verifier.schemaAt(1);
      schema.rawDatabase.execute('''
      INSERT INTO players (
        id, display_name, created_at, updated_at, version, deleted_at
      ) VALUES (
        '10000000-0000-4000-8000-000000000001',
        'Existing Player',
        '2026-08-20T00:00:00.000Z',
        '2026-08-20T00:00:00.000Z',
        0,
        NULL
      )
    ''');

      final database = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(database, 2);

      final player = await database.select(database.players).getSingle();
      expect(player.displayName, 'Existing Player');
      final tables = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name LIKE 'sync_%' ORDER BY name",
          )
          .get();
      expect(tables.map((row) => row.read<String>('name')), [
        'sync_conflicts',
        'sync_outbox_operations',
        'sync_pull_checkpoints',
      ]);

      await database.close();
      schema.close();
    },
  );
}
