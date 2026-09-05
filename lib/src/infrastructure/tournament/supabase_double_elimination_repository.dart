import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/tournament/double_elimination_service.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import 'double_elimination_codec.dart';

final class SupabaseDoubleEliminationRepository
    implements DoubleEliminationRepository {
  const SupabaseDoubleEliminationRepository(this.client);
  final SupabaseClient client;

  @override
  Future<RepositoryResult<DoubleEliminationContext>> load(
    EventId eventId,
    DivisionId divisionId,
  ) => _call('get_double_elimination_context', {
    'p_event_id': eventId.value,
    'p_division_id': divisionId.value,
  });

  @override
  Future<RepositoryResult<DoubleEliminationContext>> apply(
    DoubleEliminationCommand command,
  ) => _call('apply_double_elimination_operation', {
    'p_payload': doubleCommandJson(command),
  });

  Future<RepositoryResult<DoubleEliminationContext>> _call(
    String rpc,
    Map<String, Object?> params,
  ) async {
    try {
      final response = await client
          .rpc<Object?>(rpc, params: params)
          .timeout(const Duration(seconds: 20));
      return RepositorySuccess(decodeDoubleContext(response));
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    } on PostgrestException catch (error) {
      return RepositoryFailure(switch (error.code) {
        '42501' => const UnauthorizedFailure(
          message: 'Organizer permission is required.',
        ),
        '40001' || '23505' => const ConflictFailure(
          message: 'The bracket changed or operation identity was reused. Refresh and review.',
        ),
        '23514' => const ValidationFailure(
          field: 'tournament',
          message: 'The bracket, score, progression or lifecycle rule rejected this action.',
        ),
        'P0002' => const ValidationFailure(
          field: 'division',
          message: 'This event division is unavailable.',
        ),
        _ => const PersistenceUnavailableFailure(
          message: 'The tournament service is unavailable. No cloud success is assumed.',
        ),
      });
    } on TimeoutException {
      return const RepositoryFailure(
        PersistenceUnavailableFailure(
          message: 'The request timed out. Refresh before retrying because it may have been accepted.',
        ),
      );
    } on Exception {
      return const RepositoryFailure(
        PersistenceUnavailableFailure(
          message: 'The tournament service could not be reached safely.',
        ),
      );
    }
  }
}
