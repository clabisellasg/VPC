import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/public_events/public_event_models.dart';
import '../../application/public_events/public_event_reader.dart';
import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/money.dart';
import '../../domain/common/record_metadata.dart';
import '../../domain/common/repository_result.dart';
import '../../domain/events/event.dart';
import '../../domain/events/event_division.dart';

typedef PublicEventClock = DateTime Function();

abstract interface class PublicRowsGateway {
  Future<List<Map<String, Object?>>> fetchEvents();

  Future<List<Map<String, Object?>>> fetchEventDivisions();
}

final class SupabasePublicRowsGateway implements PublicRowsGateway {
  const SupabasePublicRowsGateway(this.client);

  final SupabaseClient client;

  static const eventTable = 'events';
  static const divisionTable = 'event_divisions';

  @override
  Future<List<Map<String, Object?>>> fetchEvents() async {
    final rows = await client
        .from(eventTable)
        .select(
          'id,name,scheduled_at,event_type,status,entry_fee_minor_units,'
          'entry_fee_currency,court_label,created_at,updated_at,version,deleted_at',
        )
        .isFilter('deleted_at', null)
        .order('scheduled_at')
        .order('id');
    return rows.map<Map<String, Object?>>((row) => Map.of(row)).toList();
  }

  @override
  Future<List<Map<String, Object?>>> fetchEventDivisions() async {
    final rows = await client
        .from(divisionTable)
        .select(
          'id,event_id,name,tournament_format,created_at,updated_at,version,deleted_at',
        )
        .isFilter('deleted_at', null)
        .order('name')
        .order('id');
    return rows.map<Map<String, Object?>>((row) => Map.of(row)).toList();
  }
}

final class SupabasePublicEventSource implements PublicEventRemoteSource {
  SupabasePublicEventSource(this.gateway, {this.clock = _utcNow});

  final PublicRowsGateway gateway;
  final PublicEventClock clock;

  @override
  Future<RepositoryResult<PublicEventCatalog>> fetchCatalog() async {
    try {
      final rows = await Future.wait([
        gateway.fetchEvents(),
        gateway.fetchEventDivisions(),
      ]);
      final events = rows[0].map(publicEventFromRow).toList();
      final divisions = rows[1].map(publicDivisionFromRow).toList();
      final eventIds = events.map((event) => event.id).toSet();
      final divisionsByEvent = <EventId, List<EventDivision>>{};
      for (final division in divisions) {
        if (!eventIds.contains(division.eventId)) {
          throw const ValidationFailure(
            field: 'event_id',
            message: 'A public division references an unavailable event.',
          );
        }
        divisionsByEvent.putIfAbsent(division.eventId, () => []).add(division);
      }
      return RepositorySuccess(
        PublicEventCatalog(
          events: events.map(
            (event) => PublicEventItem(
              event: event,
              divisions: divisionsByEvent[event.id] ?? const [],
            ),
          ),
          origin: PublicCatalogOrigin.remote,
          refreshedAt: clock().toUtc(),
        ),
      );
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    } catch (error) {
      if (error is Error) {
        rethrow;
      }
      return const RepositoryFailure(
        UnknownRepositoryFailure(
          message: 'Public event data could not be loaded safely.',
        ),
      );
    }
  }
}

Event publicEventFromRow(Map<String, Object?> row) {
  final feeUnits = row['entry_fee_minor_units'];
  final feeCurrency = row['entry_fee_currency'];
  final entryFee = switch ((feeUnits, feeCurrency)) {
    (final int units, final String currency) => Money(
      minorUnits: units,
      currencyCode: currency,
    ),
    (null, null) => null,
    _ => throw const ValidationFailure(
      field: 'entryFee',
      message: 'Public entry-fee fields are inconsistent.',
    ),
  };

  return Event(
    id: EventId(_requiredString(row, 'id')),
    name: _requiredString(row, 'name'),
    scheduledAt: _requiredTimestamp(row, 'scheduled_at'),
    type: _enumByName(
      EventType.values,
      _requiredString(row, 'event_type'),
      'event_type',
    ),
    status: _enumByName(
      EventStatus.values,
      _requiredString(row, 'status'),
      'status',
    ),
    entryFee: entryFee,
    courtLabel: _requiredString(row, 'court_label'),
    metadata: _metadata(row),
  );
}

EventDivision publicDivisionFromRow(Map<String, Object?> row) => EventDivision(
  id: DivisionId(_requiredString(row, 'id')),
  eventId: EventId(_requiredString(row, 'event_id')),
  name: _requiredString(row, 'name'),
  format: _enumByName(
    TournamentFormat.values,
    _requiredString(row, 'tournament_format'),
    'tournament_format',
  ),
  metadata: _metadata(row),
);

RecordMetadata _metadata(Map<String, Object?> row) => RecordMetadata(
  createdAt: _requiredTimestamp(row, 'created_at'),
  updatedAt: _requiredTimestamp(row, 'updated_at'),
  recordVersion: _requiredInt(row, 'version'),
  deletedAt: _optionalTimestamp(row, 'deleted_at'),
);

String _requiredString(Map<String, Object?> row, String field) {
  final value = row[field];
  if (value is String) {
    return value;
  }
  throw ValidationFailure(field: field, message: 'Public $field must be text.');
}

int _requiredInt(Map<String, Object?> row, String field) {
  final value = row[field];
  if (value is int) {
    return value;
  }
  throw ValidationFailure(
    field: field,
    message: 'Public $field must be an integer.',
  );
}

DateTime _requiredTimestamp(Map<String, Object?> row, String field) {
  final value = _optionalTimestamp(row, field);
  if (value != null) {
    return value;
  }
  throw ValidationFailure(
    field: field,
    message: 'Public $field must be a valid timestamp.',
  );
}

DateTime? _optionalTimestamp(Map<String, Object?> row, String field) {
  final value = row[field];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw ValidationFailure(
      field: field,
      message: 'Public $field must be a timestamp.',
    );
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(value)) {
    throw ValidationFailure(
      field: field,
      message: 'Public $field must include a UTC offset.',
    );
  }
  return parsed.toUtc();
}

T _enumByName<T extends Enum>(List<T> values, String name, String field) {
  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }
  throw ValidationFailure(
    field: field,
    message: 'Public $field contains an unsupported value.',
  );
}

DateTime _utcNow() => DateTime.now().toUtc();
