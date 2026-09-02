import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/events/event_setup_contracts.dart';
import '../../application/events/event_setup_models.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import 'event_setup_codec.dart';

final class SupabaseEventSetupGateway implements EventSetupRemoteGateway {
  const SupabaseEventSetupGateway(this.client);

  final SupabaseClient client;

  @override
  Future<EventSetupRemoteResult> apply(EventSetupOperation operation) async {
    try {
      final response = await client.rpc<Object?>(
        'apply_event_setup_operation',
        params: {
          'p_operation_id': operation.operationId.value,
          'p_event_id': operation.setup.event.id.value,
          'p_base_version': operation.baseVersion,
          'p_payload': eventSetupToJson(operation.setup),
        },
      );
      if (response is! Map) {
        throw const ValidationFailure(
          field: 'response',
          message: 'Cloud event response is invalid.',
        );
      }
      final map = Map<String, Object?>.from(response);
      return switch (map['status']) {
        'accepted' => EventSetupRemoteAccepted(
          setup: decodeEventSetup(map['setup']),
          replayed: map['replayed'] == true,
        ),
        'conflict' => EventSetupRemoteConflict(
          map['setup'] == null ? null : decodeEventSetup(map['setup']),
        ),
        _ => const EventSetupRemoteFailure(
          UnknownRepositoryFailure(
            message: 'Cloud event response was not recognized.',
          ),
        ),
      };
    } on DomainFailure catch (failure) {
      return EventSetupRemoteFailure(failure);
    } on PostgrestException catch (error) {
      if (error.code == '23514' &&
          error.message.contains('Tournament structure required')) {
        return const EventSetupRemoteFailure(
          TournamentStructureRequiredFailure(),
        );
      }
      if (error.code == '42501') {
        return const EventSetupRemoteFailure(
          UnauthorizedFailure(message: 'Organizer authorization is required.'),
        );
      }
      if (error.code == '23514' &&
          error.message.contains('Tournament formats')) {
        return const EventSetupRemoteFailure(TournamentFormatRequiredFailure());
      }
      if (error.code == '23505' ||
          error.code == '23514' ||
          error.code == '22023') {
        return const EventSetupRemoteFailure(
          ConflictFailure(
            message: 'The event setup conflicts with current cloud data.',
          ),
        );
      }
      return const EventSetupRemoteFailure(
        PersistenceUnavailableFailure(
          message: 'Cloud event setup is temporarily unavailable.',
        ),
      );
    }
  }

  @override
  Future<RepositoryResult<EventSetupPullPage>> pull({
    DateTime? afterUpdatedAt,
    EventId? afterId,
    int limit = 50,
  }) async {
    try {
      final response = await client.rpc<List<Object?>>(
        'pull_event_setup_changes',
        params: {
          'p_after_updated_at': afterUpdatedAt?.toIso8601String(),
          'p_after_id': afterId?.value,
          'p_limit': limit,
        },
      );
      final setups = response.map((row) {
        if (row is! Map) {
          throw const ValidationFailure(
            field: 'pull',
            message: 'Cloud pull row is invalid.',
          );
        }
        return decodeEventSetup(Map<String, Object?>.from(row)['setup']);
      }).toList();
      return RepositorySuccess(
        EventSetupPullPage(setups: setups, hasMore: setups.length == limit),
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
                message: 'Cloud event refresh is unavailable.',
              ),
      );
    }
  }
}
