import '../common/domain_enums.dart';
import '../common/domain_failure.dart';
import '../common/entity_id.dart';
import '../common/repository_result.dart';
import 'event.dart';

final class EventQuery {
  EventQuery({
    Iterable<EventStatus> statuses = const [],
    this.type,
    int limit = 50,
  }) : statuses = Set<EventStatus>.unmodifiable(statuses),
       limit = limit {
    if (limit <= 0) {
      throw const ValidationFailure(
        field: 'limit',
        message: 'Query limit must be positive.',
      );
    }
  }

  final Set<EventStatus> statuses;
  final EventType? type;
  final int limit;
}

abstract interface class EventRepository {
  Future<RepositoryResult<Event>> getById(EventId id);

  Stream<RepositoryResult<List<Event>>> observe(EventQuery query);

  Future<RepositoryResult<Event>> save(Event event, {int? expectedVersion});
}
