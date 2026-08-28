import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/domain/common/domain_failure.dart';
import 'package:vpc/src/infrastructure/public_events/supabase_public_event_source.dart';

void main() {
  test(
    'maps validated public rows and requests only events and divisions',
    () async {
      final gateway = _FakeRowsGateway();
      final result = await SupabasePublicEventSource(
        gateway,
        clock: () => DateTime.utc(2026, 8, 28, 4),
      ).fetchCatalog();

      expect(gateway.eventRequests, 1);
      expect(gateway.divisionRequests, 1);
      result.when(
        success: (catalog) {
          expect(catalog.events.single.event.name, 'VPC Demo Event');
          expect(catalog.events.single.divisions.single.name, 'Sample Open');
          expect(catalog.refreshedAt, DateTime.utc(2026, 8, 28, 4));
        },
        failure: (failure) => fail(failure.message),
      );
      expect(SupabasePublicRowsGateway.eventTable, 'events');
      expect(SupabasePublicRowsGateway.divisionTable, 'event_divisions');
    },
  );

  test('rejects an invalid UUID without exposing row contents', () async {
    final gateway = _FakeRowsGateway(events: [_eventRow(id: 'invalid')]);
    final result = await SupabasePublicEventSource(gateway).fetchCatalog();

    result.when(
      success: (_) => fail('Expected mapping failure.'),
      failure: (failure) => expect(failure, isA<ValidationFailure>()),
    );
  });

  test('rejects unsupported status', () async {
    final gateway = _FakeRowsGateway(events: [_eventRow(status: 'cancelled')]);
    final result = await SupabasePublicEventSource(gateway).fetchCatalog();

    result.when(
      success: (_) => fail('Expected mapping failure.'),
      failure: (failure) => expect(failure, isA<ValidationFailure>()),
    );
  });

  test('rejects timestamp without an explicit UTC offset', () async {
    final gateway = _FakeRowsGateway(
      events: [_eventRow(scheduledAt: '2026-08-28 02:00:00')],
    );
    final result = await SupabasePublicEventSource(gateway).fetchCatalog();

    result.when(
      success: (_) => fail('Expected mapping failure.'),
      failure: (failure) => expect(failure, isA<ValidationFailure>()),
    );
  });

  test('redacts infrastructure exceptions into a safe failure', () async {
    final result = await SupabasePublicEventSource(_ThrowingGateway())
        .fetchCatalog();

    result.when(
      success: (_) => fail('Expected repository failure.'),
      failure: (failure) {
        expect(failure, isA<UnknownRepositoryFailure>());
        expect(failure.message, isNot(contains('private-token')));
      },
    );
  });

  test('rejects an orphan public division', () async {
    final result = await SupabasePublicEventSource(
      _FakeRowsGateway(
        divisions: [
          _divisionRow(eventId: '71000000-0000-4000-8000-000000000099'),
        ],
      ),
    ).fetchCatalog();

    result.when(
      success: (_) => fail('Expected relationship mapping failure.'),
      failure: (failure) => expect(failure, isA<ValidationFailure>()),
    );
  });
}

class _FakeRowsGateway implements PublicRowsGateway {
  _FakeRowsGateway({
    List<Map<String, Object?>>? events,
    List<Map<String, Object?>>? divisions,
  }) : events = events ?? [_eventRow()],
       divisions = divisions ?? [_divisionRow()];

  final List<Map<String, Object?>> events;
  final List<Map<String, Object?>> divisions;
  var eventRequests = 0;
  var divisionRequests = 0;

  @override
  Future<List<Map<String, Object?>>> fetchEvents() async {
    eventRequests++;
    return events;
  }

  @override
  Future<List<Map<String, Object?>>> fetchEventDivisions() async {
    divisionRequests++;
    return divisions;
  }
}

class _ThrowingGateway implements PublicRowsGateway {
  @override
  Future<List<Map<String, Object?>>> fetchEventDivisions() =>
      throw Exception('private-token');

  @override
  Future<List<Map<String, Object?>>> fetchEvents() =>
      throw Exception('private-token');
}

Map<String, Object?> _eventRow({
  String id = '71000000-0000-4000-8000-000000000001',
  String status = 'inProgress',
  String scheduledAt = '2026-08-28T02:00:00Z',
}) => {
  'id': id,
  'name': 'VPC Demo Event',
  'scheduled_at': scheduledAt,
  'event_type': 'formal',
  'status': status,
  'entry_fee_minor_units': 0,
  'entry_fee_currency': 'PHP',
  'court_label': 'VPC Sample Court',
  'created_at': '2026-08-01T00:00:00Z',
  'updated_at': '2026-08-20T00:00:00Z',
  'version': 0,
  'deleted_at': null,
};

Map<String, Object?> _divisionRow({
  String eventId = '71000000-0000-4000-8000-000000000001',
}) => {
  'id': '72000000-0000-4000-8000-000000000001',
  'event_id': eventId,
  'name': 'Sample Open',
  'tournament_format': 'singleRoundRobin',
  'created_at': '2026-08-01T00:00:00Z',
  'updated_at': '2026-08-20T00:00:00Z',
  'version': 0,
  'deleted_at': null,
};
