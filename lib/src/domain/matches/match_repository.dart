import '../common/entity_id.dart';
import '../common/repository_result.dart';
import 'match.dart';

abstract interface class MatchRepository {
  Future<RepositoryResult<Match>> getById(MatchId id);

  Stream<RepositoryResult<List<Match>>> observeForDivision(
    DivisionId divisionId,
  );

  Future<RepositoryResult<Match>> save(Match match, {int? expectedVersion});
}
