import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/participation/participation_contracts.dart';
import '../../application/participation/participation_models.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import 'participation_codec.dart';

final class SupabaseParticipationGateway implements ParticipationRemoteGateway {
  const SupabaseParticipationGateway(this.client);
  final SupabaseClient client;

  @override
  Future<ParticipationRemoteResult> apply(
    ParticipationOperation operation,
  ) async {
    try {
      final response = await client.rpc<Object?>(
        'apply_participation_operation',
        params: {
          'p_operation_id': operation.operationId.value,
          'p_event_participant_id': operation.record.participant.id.value,
          'p_base_version': operation.baseVersion,
          'p_payload': participationToJson(operation.record),
        },
      );
      if (response is! Map) {
        throw const ValidationFailure(
          field: 'response',
          message: 'Cloud participation response is invalid.',
        );
      }
      final map = Map<String, Object?>.from(response);
      return switch (map['status']) {
        'accepted' => ParticipationRemoteAccepted(
          record: decodeParticipation(map['participation']),
          replayed: map['replayed'] == true,
        ),
        'conflict' => ParticipationRemoteConflict(
          map['participation'] == null
              ? null
              : decodeParticipation(map['participation']),
        ),
        _ => const ParticipationRemoteFailure(
          UnknownRepositoryFailure(
            message: 'Cloud participation response was not recognized.',
          ),
        ),
      };
    } on DomainFailure catch (failure) {
      return ParticipationRemoteFailure(failure);
    } on PostgrestException catch (error) {
      if (error.code == '42501') {
        return const ParticipationRemoteFailure(
          UnauthorizedFailure(message: 'Organizer authorization is required.'),
        );
      }
      if (error.code == '23505' ||
          error.code == '23514' ||
          error.code == '22023') {
        return ParticipationRemoteFailure(
          ConflictFailure(message: _safeMessage(error.message)),
        );
      }
      return const ParticipationRemoteFailure(
        PersistenceUnavailableFailure(
          message: 'Cloud participation is temporarily unavailable.',
        ),
      );
    }
  }

  @override
  Future<RepositoryResult<ParticipationPullPage>> pull({
    DateTime? afterUpdatedAt,
    EventParticipantId? afterId,
    int limit = 50,
  }) async {
    try {
      final response = await client.rpc<List<Object?>>(
        'pull_participation_changes',
        params: {
          'p_after_updated_at': afterUpdatedAt?.toIso8601String(),
          'p_after_id': afterId?.value,
          'p_limit': limit,
        },
      );
      final records = response.map((row) {
        if (row is! Map) {
          throw const ValidationFailure(
            field: 'pull',
            message: 'Cloud pull row is invalid.',
          );
        }
        return decodeParticipation(
          Map<String, Object?>.from(row)['participation'],
        );
      }).toList();
      return RepositorySuccess(
        ParticipationPullPage(
          records: records,
          hasMore: records.length == limit,
        ),
      );
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    } on PostgrestException catch (error) {
      return RepositoryFailure(
        error.code == '42501'
            ? const UnauthorizedFailure(
                message: 'Organizer authorization is required.',
              )
            : const PersistenceUnavailableFailure(
                message: 'Cloud roster refresh is unavailable.',
              ),
      );
    }
  }
}

String _safeMessage(String message) => message.contains('lifecycle')
    ? 'The event lifecycle does not permit this participation change.'
    : 'Participation conflicts with current cloud data.';
