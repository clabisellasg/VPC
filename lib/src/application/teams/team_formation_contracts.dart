import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import 'team_formation_models.dart';

abstract interface class TeamIdFactory {
  TeamId nextTeamId();
  SyncOperationId nextOperationId();
}

abstract interface class TeamRandomSource {
  List<T> shuffled<T>(List<T> values);
}

abstract interface class TeamFormationStore {
  Future<RepositoryResult<TeamFormationSnapshot>> load(
    EventId eventId,
    DivisionId divisionId,
  );

  Future<RepositoryResult<TeamFormationSnapshot>> replace({
    required TeamFormationSnapshot current,
    required TeamFormationPreview preview,
    required SyncOperationId operationId,
  });
}
