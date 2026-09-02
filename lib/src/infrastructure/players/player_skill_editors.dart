import '../../application/players/player_directory_reader.dart';
import '../../application/players/player_skill_editor.dart';
import '../../application/sync/sync_contracts.dart';
import '../../application/sync/sync_models.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/record_metadata.dart';
import '../../domain/common/repository_result.dart';
import '../../domain/players/permanent_player.dart';
import '../../domain/players/player_repository.dart';
import '../../domain/players/player_skill.dart';

final class AndroidPlayerSkillEditor implements PlayerSkillEditor {
  const AndroidPlayerSkillEditor(this.repository, this.coordinator);
  final PlayerRepository repository;
  final SyncCoordinator? coordinator;
  @override
  Future<RepositoryResult<PermanentPlayer>> update(
    PlayerId id,
    PlayerSkill? skill,
  ) async {
    final current = await repository.getById(id);
    if (current case RepositoryFailure(:final failure)) {
      return RepositoryFailure(failure);
    }
    final player = (current as RepositorySuccess<PermanentPlayer>).value;
    final now = DateTime.now().toUtc();
    final updated = PermanentPlayer(
      id: id,
      displayName: player.displayName,
      skill: skill,
      metadata: RecordMetadata(
        createdAt: player.metadata.createdAt,
        updatedAt: now,
        recordVersion: player.metadata.recordVersion + 1,
      ),
    );
    final saved = await repository.save(updated);
    if (saved case RepositoryFailure(:final failure)) {
      return RepositoryFailure(failure);
    }
    await coordinator?.synchronize();
    return RepositorySuccess(updated);
  }
}

final class WebPlayerSkillEditor implements PlayerSkillEditor {
  const WebPlayerSkillEditor(this.reader, this.remote, this.ids, this.clock);
  final PlayerDirectoryReader reader;
  final SyncRemoteGateway remote;
  final SyncIdFactory ids;
  final SyncClock clock;
  @override
  Future<RepositoryResult<PermanentPlayer>> update(
    PlayerId id,
    PlayerSkill? skill,
  ) async {
    final found = await reader.getById(id);
    if (found case RepositoryFailure(:final failure)) {
      return RepositoryFailure(failure);
    }
    final current = (found as RepositorySuccess).value.profile.toPlayer();
    final now = clock.nowUtc();
    final updated = PermanentPlayer(
      id: id,
      displayName: current.displayName,
      skill: skill,
      metadata: RecordMetadata(
        createdAt: current.metadata.createdAt,
        updatedAt: now,
        recordVersion: current.metadata.recordVersion + 1,
      ),
    );
    final result = await remote.applyPlayerOperation(
      SyncOperation(
        id: ids.operationId(),
        entityType: SyncEntityType.player,
        entityId: id,
        kind: SyncOperationKind.upsert,
        baseVersion: current.metadata.recordVersion,
        payload: PlayerSyncPayload.fromPlayer(updated),
        createdAt: now,
        attemptCount: 0,
        nextEligibleAt: now,
        status: SyncOperationStatus.pending,
      ),
    );
    return switch (result) {
      RemoteApplyAccepted(:final player) => RepositorySuccess(player),
      RemoteApplyConflict() => const RepositoryFailure(
        ConflictFailure(
          message: 'Player skill changed elsewhere. Refresh and try again.',
        ),
      ),
      RemoteApplyFailure(kind: SyncFailureKind.authorizationBlocked) =>
        const RepositoryFailure(
          UnauthorizedFailure(message: 'Organizer permission is required.'),
        ),
      RemoteApplyFailure(:final safeMessage) => RepositoryFailure(
        PersistenceUnavailableFailure(message: safeMessage),
      ),
    };
  }
}

final class UnavailablePlayerSkillEditor implements PlayerSkillEditor {
  const UnavailablePlayerSkillEditor();
  @override
  Future<RepositoryResult<PermanentPlayer>> update(
    PlayerId id,
    PlayerSkill? skill,
  ) async => const RepositoryFailure(
    PersistenceUnavailableFailure(
      message: 'Player skill editing is unavailable.',
    ),
  );
}
