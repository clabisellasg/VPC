import 'dart:convert';

import '../../application/events/event_setup_models.dart';
import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/money.dart';
import '../../domain/common/record_metadata.dart';
import '../../domain/events/event.dart';
import '../../domain/events/event_division.dart';

Map<String, Object?> eventSetupToJson(EventSetup setup) => {
  'event': _eventToJson(setup.event),
  'divisions': setup.divisions.map(_divisionToJson).toList(),
};

String encodeEventSetup(EventSetup setup) =>
    jsonEncode(eventSetupToJson(setup));

EventSetup decodeEventSetup(Object? value) {
  final object = value is String ? jsonDecode(value) : value;
  if (object is! Map) {
    throw const ValidationFailure(
      field: 'setup',
      message: 'Event setup must be an object.',
    );
  }
  final map = Map<String, Object?>.from(object);
  final eventMap = map['event'];
  final divisionList = map['divisions'];
  if (eventMap is! Map || divisionList is! List) {
    throw const ValidationFailure(
      field: 'setup',
      message: 'Event setup fields are invalid.',
    );
  }
  final event = _eventFromJson(Map<String, Object?>.from(eventMap));
  return EventSetup(
    event: event,
    readiness: _readiness(map['readiness']),
    divisions: divisionList.map((value) {
      if (value is! Map) {
        throw const ValidationFailure(
          field: 'division',
          message: 'Division must be an object.',
        );
      }
      return _divisionFromJson(Map<String, Object?>.from(value));
    }),
  );
}

Map<DivisionId, DivisionTournamentReadiness> _readiness(Object? value) {
  if (value == null) return const {};
  if (value is! List) {
    throw const ValidationFailure(
      field: 'readiness',
      message: 'Invalid tournament readiness data.',
    );
  }
  final result = <DivisionId, DivisionTournamentReadiness>{};
  for (final item in value) {
    if (item is! Map<String, Object?>) {
      throw const ValidationFailure(
        field: 'readiness',
        message: 'Invalid tournament readiness row.',
      );
    }
    final id = DivisionId(_string(item, 'division_id'));
    final teams = _int(item, 'complete_teams');
    final active = _int(item, 'active_matches');
    final generated = _int(item, 'generated_matches');
    if (teams < 0 ||
        active < 0 ||
        generated < active ||
        result.containsKey(id)) {
      throw const ValidationFailure(
        field: 'readiness',
        message: 'Invalid tournament readiness counts.',
      );
    }
    result[id] = DivisionTournamentReadiness(
      completeTeams: teams,
      activeMatches: active,
      generatedMatches: generated,
    );
  }
  return result;
}

Map<String, Object?> _eventToJson(Event event) => {
  'id': event.id.value,
  'name': event.name,
  'scheduled_at': event.scheduledAt.toIso8601String(),
  'event_type': event.type.name,
  'status': event.status.name,
  'entry_fee_minor_units': event.entryFee?.minorUnits,
  'entry_fee_currency': event.entryFee?.currencyCode,
  'court_label': event.courtLabel,
  ..._metadataToJson(event.metadata),
};

Map<String, Object?> _divisionToJson(EventDivision division) => {
  'id': division.id.value,
  'event_id': division.eventId.value,
  'name': division.name,
  'tournament_format': division.format?.name,
  ..._metadataToJson(division.metadata),
};

Map<String, Object?> _metadataToJson(RecordMetadata metadata) => {
  'created_at': metadata.createdAt.toIso8601String(),
  'updated_at': metadata.updatedAt.toIso8601String(),
  'version': metadata.recordVersion,
  'deleted_at': metadata.deletedAt?.toIso8601String(),
};

Event _eventFromJson(Map<String, Object?> row) {
  final feeUnits = row['entry_fee_minor_units'];
  final feeCurrency = row['entry_fee_currency'];
  return Event(
    id: EventId(_string(row, 'id')),
    name: _string(row, 'name'),
    scheduledAt: _time(row, 'scheduled_at')!,
    type: _enum(EventType.values, _string(row, 'event_type'), 'event_type'),
    status: _enum(EventStatus.values, _string(row, 'status'), 'status'),
    entryFee: feeUnits == null && feeCurrency == null
        ? null
        : Money(
            minorUnits: _int(row, 'entry_fee_minor_units'),
            currencyCode: _string(row, 'entry_fee_currency'),
          ),
    courtLabel: _string(row, 'court_label'),
    metadata: _metadata(row),
  );
}

EventDivision _divisionFromJson(Map<String, Object?> row) => EventDivision(
  id: DivisionId(_string(row, 'id')),
  eventId: EventId(_string(row, 'event_id')),
  name: _string(row, 'name'),
  format: row['tournament_format'] == null
      ? null
      : _enum(
          TournamentFormat.values,
          _string(row, 'tournament_format'),
          'tournament_format',
        ),
  metadata: _metadata(row),
);

RecordMetadata _metadata(Map<String, Object?> row) => RecordMetadata(
  createdAt: _time(row, 'created_at')!,
  updatedAt: _time(row, 'updated_at')!,
  recordVersion: _int(row, 'version'),
  deletedAt: _time(row, 'deleted_at'),
);

String _string(Map<String, Object?> row, String field) {
  final value = row[field];
  if (value is String) return value;
  throw ValidationFailure(field: field, message: '$field must be text.');
}

int _int(Map<String, Object?> row, String field) {
  final value = row[field];
  if (value is int) return value;
  throw ValidationFailure(field: field, message: '$field must be an integer.');
}

DateTime? _time(Map<String, Object?> row, String field) {
  final value = row[field];
  if (value == null) return null;
  if (value is! String) {
    throw ValidationFailure(
      field: field,
      message: '$field must be a timestamp.',
    );
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(value)) {
    throw ValidationFailure(
      field: field,
      message: '$field must include a UTC offset.',
    );
  }
  return parsed.toUtc();
}

T _enum<T extends Enum>(List<T> values, String name, String field) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw ValidationFailure(field: field, message: '$field is unsupported.');
}
