/// Returns a SQLite timestamp in a form Drift can bind in another SQL query.
///
/// Raw `customSelect` rows expose ISO-8601 timestamp columns as [String] while
/// some test and typed-query paths expose [DateTime]. Cross-outbox ordering must
/// accept both representations instead of casting raw SQLite text to DateTime.
Object outboxCreatedAt(Map<String, Object?> row) {
  final value = row['created_at'];
  if (value is String) return value;
  if (value is DateTime) return value;
  throw const FormatException('Outbox created_at is missing or invalid.');
}
