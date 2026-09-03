import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/tournament/single_elimination_service.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import 'bracket_codec.dart';

final class SupabaseBracketRepository implements BracketRepository {
  const SupabaseBracketRepository(this.client);
  final SupabaseClient client;
  @override
  Future<RepositoryResult<BracketContext>> load(
    EventId eventId,
    DivisionId divisionId,
  ) => _call('get_single_elimination_context', {
    'p_event_id': eventId.value,
    'p_division_id': divisionId.value,
  });
  @override
  Future<RepositoryResult<BracketContext>> apply(BracketCommand command) =>
      _call('apply_single_elimination_operation', {
        'p_payload': commandJson(command),
      });
  Future<RepositoryResult<BracketContext>> _call(
    String rpc,
    Map<String, Object?> params,
  ) async {
    try {
      final response = await client
          .rpc<Object?>(rpc, params: params)
          .timeout(const Duration(seconds: 20));
      return RepositorySuccess(decodeBracketContext(response));
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    } on PostgrestException catch (error) {
      return RepositoryFailure(switch (error.code) {
        '42501' => const UnauthorizedFailure(
          message: 'Organizer permission is required.',
        ),
        '40001' || '23505' => const ConflictFailure(
          message: 'The bracket changed or this operation identity was reused. Refresh and review the conflict.',
        ),
        '23514' => const ValidationFailure(
          field: 'tournament',
          message: 'This action is not allowed by the bracket, score or event lifecycle rules.',
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
          message: 'The request timed out. Refresh before retrying; the server may have accepted it.',
        ),
      );
    } on Exception {
      return const RepositoryFailure(
        PersistenceUnavailableFailure(
          message: 'The tournament service could not be reached safely. Refresh before retrying.',
        ),
      );
    }
  }
}
