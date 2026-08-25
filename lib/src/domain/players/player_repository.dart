import '../common/domain_failure.dart';
import '../common/domain_validation.dart';
import '../common/entity_id.dart';
import '../common/repository_result.dart';
import 'permanent_player.dart';

final class PlayerSearchQuery {
  factory PlayerSearchQuery({String? nameContains, int limit = 50}) {
    if (limit <= 0) {
      throw const ValidationFailure(
        field: 'limit',
        message: 'Search limit must be positive.',
      );
    }
    return PlayerSearchQuery._(
      nameContains: nameContains == null
          ? null
          : requireNonBlank(nameContains, field: 'nameContains'),
      limit: limit,
    );
  }

  const PlayerSearchQuery._({required this.nameContains, required this.limit});

  final String? nameContains;
  final int limit;
}

abstract interface class PlayerRepository {
  Future<RepositoryResult<PermanentPlayer>> getById(PlayerId id);

  Stream<RepositoryResult<List<PermanentPlayer>>> observe(
    PlayerSearchQuery query,
  );

  Future<RepositoryResult<PermanentPlayer>> save(
    PermanentPlayer player, {
    int? expectedVersion,
  });
}
