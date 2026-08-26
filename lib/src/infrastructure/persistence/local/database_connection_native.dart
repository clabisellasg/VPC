import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

const localDatabaseName = 'vpc';

QueryExecutor openAndroidDatabaseConnection() {
  if (!Platform.isAndroid) {
    throw UnsupportedError(
      'Production SQLite persistence is supported only on Android.',
    );
  }

  return driftDatabase(
    name: localDatabaseName,
    native: DriftNativeOptions(
      databaseDirectory: getApplicationSupportDirectory,
      shareAcrossIsolates: true,
      setup: (database) {
        database.execute('PRAGMA foreign_keys = ON');
      },
    ),
  );
}

QueryExecutor openInMemoryDatabaseConnection() => NativeDatabase.memory(
  setup: (database) {
    database.execute('PRAGMA foreign_keys = ON');
  },
);
