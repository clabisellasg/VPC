import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import 'player_directory_models.dart';

abstract interface class PlayerDirectoryReader {
  Future<RepositoryResult<PlayerDirectoryPage>> readPage(
    PlayerDirectoryQuery query,
  );

  Future<RepositoryResult<PlayerDirectoryPage>> refreshPage(
    PlayerDirectoryQuery query,
  );

  Future<RepositoryResult<PlayerDirectoryEntry>> getById(PlayerId id);
}

abstract interface class PlayerDirectoryRemoteSource {
  Future<RepositoryResult<PlayerDirectoryPage>> fetchPage(
    PlayerDirectoryQuery query,
  );

  Future<RepositoryResult<PlayerDirectoryEntry>> fetchById(PlayerId id);
}

abstract interface class PlayerDirectoryCache {
  Future<RepositoryResult<PlayerDirectoryPage>> readPage(
    PlayerDirectoryQuery query,
  );

  Future<RepositoryResult<PlayerDirectoryEntry>> getById(PlayerId id);

  Future<RepositoryResult<void>> reconcile(PlayerDirectoryPage remotePage);
}

abstract interface class PlayerCreationWriter {
  Future<RepositoryResult<CreatedPlayer>> create(PublicPlayerProfile player);
}

abstract interface class PlayerIdFactory {
  PlayerId createPlayerId();
}

abstract interface class PlayerDirectoryClock {
  DateTime nowUtc();
}
