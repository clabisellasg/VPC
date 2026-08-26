import 'package:drift/native.dart';

import '../../../domain/common/domain_failure.dart';

DomainFailure? mapExpectedSqliteFailure(
  Object error, {
  required String operation,
}) {
  if (error is SqliteException && error.resultCode == 19) {
    return ConflictFailure(
      message: '$operation violated a local database constraint.',
    );
  }
  return null;
}
