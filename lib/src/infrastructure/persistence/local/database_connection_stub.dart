import 'package:drift/drift.dart';

QueryExecutor openAndroidDatabaseConnection() => throw UnsupportedError(
  'Android SQLite persistence is unavailable on this platform.',
);

QueryExecutor openInMemoryDatabaseConnection() => throw UnsupportedError(
  'In-memory SQLite persistence is unavailable on this platform.',
);
