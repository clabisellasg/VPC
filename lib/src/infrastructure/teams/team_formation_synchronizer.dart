import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import 'drift_team_formation_store.dart';
import 'supabase_team_formation_store.dart';
import 'team_formation_puller.dart';

final class TeamFormationSynchronizer {
  TeamFormationSynchronizer({required this.local, required this.remote});
  final DriftTeamFormationStore local;
  final SupabaseTeamFormationStore remote;
  bool _running = false;
  Future<void> synchronize() async {
    if (_running) return;
    _running = true;
    try {
      for (final operation in await local.pendingOperations()) {
        final loaded = await remote.load(
          EventId(operation.eventId),
          DivisionId(operation.divisionId),
        );
        if (loaded case RepositoryFailure(:final failure)) {
          await local.markOperation(
            operation.id,
            failure is UnauthorizedFailure ? 'blocked' : 'failed',
            failure.message,
          );
          continue;
        }
        final snapshot = (loaded as RepositorySuccess).value;
        final preview = await local.decodePending(operation, snapshot);
        final applied = await remote.replace(
          current: snapshot,
          preview: preview,
          operationId: SyncOperationId(operation.id),
        );
        if (applied case RepositorySuccess()) {
          await local.acceptOperation(operation.id);
        } else if (applied case RepositoryFailure(:final failure)) {
          await local.markOperation(
            operation.id,
            failure is ConflictFailure
                ? 'conflicted'
                : failure is UnauthorizedFailure
                ? 'blocked'
                : 'failed',
            failure.message,
          );
        }
      }
      await TeamFormationPuller(local: local, remote: remote).pull();
    } finally {
      _running = false;
    }
  }

  Future<void> synchronizeDivision(
    EventId eventId,
    DivisionId divisionId,
  ) async {
    await synchronize();
  }
}
