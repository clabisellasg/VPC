import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/court/court_queue_service.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import 'court_queue_codec.dart';

final class SupabaseCourtQueueRepository implements CourtQueueRepository {
  const SupabaseCourtQueueRepository(this.client);
  final SupabaseClient client;

  @override
  Future<RepositoryResult<CourtQueueSnapshot>> load(EventId eventId) =>
      _call('get_court_queue_context', {'p_event_id': eventId.value});

  @override
  Future<RepositoryResult<CourtQueueSnapshot>> reconcile(
    CourtQueueCommand command,
  ) => _call('apply_court_queue_operation', {
    'p_payload': courtCommandJson(command),
  });

  @override
  Future<RepositoryResult<CourtQueueSnapshot>> start(
    CourtQueueCommand command,
  ) => _call('apply_court_queue_operation', {
    'p_payload': courtCommandJson(command),
  });

  Future<RepositoryResult<CourtQueueSnapshot>> _call(
    String name,
    Map<String, Object?> params,
  ) async {
    try {
      final value = await client
          .rpc<Object?>(name, params: params)
          .timeout(const Duration(seconds: 20));
      return RepositorySuccess(decodeCourtSnapshot(value));
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    } on PostgrestException catch (error) {
      return RepositoryFailure(switch (error.code) {
        '42501' => const UnauthorizedFailure(
          message: 'Organizer permission is required.',
        ),
        '40001' || '23505' => const ConflictFailure(
          message: 'The court queue changed. Refresh and retry.',
        ),
        '23514' => const ValidationFailure(
          field: 'queue',
          message: 'The selected match is not eligible for this court.',
        ),
        'P0002' => const ValidationFailure(
          field: 'event',
          message: 'This event is unavailable.',
        ),
        _ => const PersistenceUnavailableFailure(
          message:
              'The court service is unavailable. No cloud success is assumed.',
        ),
      });
    } on TimeoutException {
      return const RepositoryFailure(
        PersistenceUnavailableFailure(
          message: 'The court request timed out. Refresh before retrying.',
        ),
      );
    } on Exception {
      return const RepositoryFailure(
        PersistenceUnavailableFailure(
          message: 'The court service could not be reached safely.',
        ),
      );
    }
  }
}
