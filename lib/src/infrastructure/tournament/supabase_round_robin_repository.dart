import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/tournament/round_robin_service.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import 'round_robin_codec.dart';

final class SupabaseRoundRobinRepository implements RoundRobinRepository {
  const SupabaseRoundRobinRepository(this.client);
  final SupabaseClient client;
  @override
  Future<RepositoryResult<RoundRobinContext>> load(EventId e, DivisionId d) =>
      _call('get_round_robin_context', {
        'p_event_id': e.value,
        'p_division_id': d.value,
      });
  @override
  Future<RepositoryResult<RoundRobinContext>> apply(RoundRobinCommand c) =>
      _call('apply_round_robin_operation', {
        'p_payload': roundRobinCommandJson(c),
      });
  Future<RepositoryResult<RoundRobinContext>> _call(
    String rpc,
    Map<String, Object?> params,
  ) async {
    try {
      return RepositorySuccess(
        decodeRoundRobinContext(
          await client
              .rpc<Object?>(rpc, params: params)
              .timeout(const Duration(seconds: 20)),
        ),
      );
    } on DomainFailure catch (f) {
      return RepositoryFailure(f);
    } on PostgrestException catch (e) {
      return RepositoryFailure(switch (e.code) {
        '42501' => const UnauthorizedFailure(
          message: 'Organizer permission is required.',
        ),
        '40001' || '23505' => const ConflictFailure(
          message: 'The schedule changed or this operation identity was reused. Refresh and review.',
        ),
        '23514' => const ValidationFailure(
          field: 'roundRobin',
          message: 'This action is not allowed by the schedule, score or lifecycle rules.',
        ),
        'P0002' => const NotFoundFailure(
          entity: 'Division',
          identifier: 'requested',
        ),
        _ => const PersistenceUnavailableFailure(
          message: 'The tournament service is unavailable. No cloud success is assumed.',
        ),
      });
    } on TimeoutException {
      return const RepositoryFailure(
        PersistenceUnavailableFailure(
          message: 'The request timed out. Refresh before retrying; it may have been accepted.',
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
