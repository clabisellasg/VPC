import '../../domain/common/domain_failure.dart';
import '../../domain/common/record_metadata.dart';
import '../../domain/common/repository_result.dart';
import 'player_directory_models.dart';
import 'player_directory_reader.dart';

final class PlayerCreationService {
  const PlayerCreationService({
    required this.reader,
    required this.writer,
    required this.idFactory,
    required this.clock,
  });

  final PlayerDirectoryReader reader;
  final PlayerCreationWriter writer;
  final PlayerIdFactory idFactory;
  final PlayerDirectoryClock clock;

  Future<PlayerCreationResult> create({
    required String requestedDisplayName,
    required bool duplicateAcknowledged,
  }) async {
    late final String displayName;
    try {
      displayName = preparePlayerDisplayName(requestedDisplayName);
    } on DomainFailure catch (failure) {
      return PlayerCreationFailed(failure);
    }

    final normalized = normalizePlayerName(displayName);
    final duplicateResult = await reader.readPage(
      PlayerDirectoryQuery(searchText: normalized),
    );
    if (duplicateResult case RepositoryFailure<PlayerDirectoryPage>(
      :final failure,
    )) {
      return PlayerCreationFailed(failure);
    }
    final page =
        (duplicateResult as RepositorySuccess<PlayerDirectoryPage>).value;
    final candidates = page.entries
        .map((entry) => entry.profile)
        .where(
          (profile) => normalizePlayerName(profile.displayName) == normalized,
        )
        .toList(growable: false);
    if (candidates.isNotEmpty && !duplicateAcknowledged) {
      return PlayerDuplicateWarning(candidates);
    }

    final now = clock.nowUtc();
    if (!now.isUtc) {
      return const PlayerCreationFailed(
        ValidationFailure(
          field: 'clock',
          message: 'Player creation clock must return UTC.',
        ),
      );
    }
    final player = PublicPlayerProfile(
      id: idFactory.createPlayerId(),
      displayName: displayName,
      metadata: RecordMetadata(
        createdAt: now,
        updatedAt: now,
        recordVersion: 0,
      ),
    );
    final result = await writer.create(player);
    return result.when<PlayerCreationResult>(
      success: PlayerCreated.new,
      failure: PlayerCreationFailed.new,
    );
  }
}
