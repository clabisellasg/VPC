import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/events/event_setup_contracts.dart';
import 'package:vpc/src/application/events/event_setup_models.dart';
import 'package:vpc/src/application/events/event_setup_service.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/record_metadata.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/events/event.dart';
import 'package:vpc/src/domain/events/event_division.dart';

void main() {
  late _Writer writer;
  late EventSetupService service;
  setUp(() {
    writer = _Writer();
    service = EventSetupService(
      writer: writer,
      idFactory: _Ids(),
      clock: const _Clock(),
    );
  });

  test(
    'quick casual creates upcoming Open division with null format',
    () async {
      final result = await service.createQuickCasual(
        name: '  Casual   Play  ',
        scheduledAt: DateTime.utc(2026, 9, 10, 8),
        venue: ' Community Court ',
      );
      expect(result, isA<EventSetupSaved>());
      expect(writer.last!.event.type, EventType.casual);
      expect(writer.last!.event.status, EventStatus.upcoming);
      expect(writer.last!.divisions.single.name, 'Open');
      expect(writer.last!.divisions.single.format, isNull);
    },
  );

  test(
    'formal setup requires one division and stores all formats as null',
    () async {
      final failed = await service.createFormal(
        name: 'Sample Formal',
        scheduledAt: DateTime.utc(2026, 9, 10, 8),
        venue: 'Court',
        divisionNames: const [],
      );
      expect(failed, isA<EventSetupMutationFailed>());
      final saved = await service.createFormal(
        name: 'Sample Formal',
        scheduledAt: DateTime.utc(2026, 9, 10, 8),
        venue: 'Court',
        divisionNames: const ['Open', 'Mixed'],
      );
      expect(saved, isA<EventSetupSaved>());
      expect(
        writer.last!.divisions.every((division) => division.format == null),
        isTrue,
      );
    },
  );

  test('normalized duplicate division names are rejected', () async {
    final result = await service.createFormal(
      name: 'Sample Formal',
      scheduledAt: DateTime.utc(2026, 9, 10, 8),
      venue: 'Court',
      divisionNames: const ['Open', '  OPEN  '],
    );
    expect(result, isA<EventSetupMutationFailed>());
  });

  test(
    'registration is allowed with null format but in-progress is blocked',
    () async {
      final setup = _setup(status: EventStatus.upcoming, format: null);
      final registration = await service.advance(setup);
      expect(registration, isA<EventSetupSaved>());
      final blocked = await service.advance(
        _setup(status: EventStatus.registration, format: null),
      );
      expect(
        (blocked as EventSetupMutationFailed).failure.code,
        'tournament_format_required',
      );
    },
  );

  test('preconfigured event advances through later lifecycle states', () async {
    for (final status in [
      EventStatus.registration,
      EventStatus.inProgress,
      EventStatus.completed,
    ]) {
      final result = await service.advance(
        _setup(status: status, format: TournamentFormat.singleElimination),
      );
      expect(result, isA<EventSetupSaved>());
    }
    expect(
      await service.advance(
        _setup(
          status: EventStatus.archived,
          format: TournamentFormat.singleElimination,
        ),
      ),
      isA<EventSetupMutationFailed>(),
    );
  });
}

EventSetup _setup({
  required EventStatus status,
  required TournamentFormat? format,
}) {
  final version = EventStatus.values.indexOf(status);
  final metadata = RecordMetadata(
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1, 0, version),
    recordVersion: version,
  );
  final eventId = EventId('91000000-0000-4000-8000-000000000001');
  return EventSetup(
    event: Event(
      id: eventId,
      name: 'VPC M9 Fixture',
      scheduledAt: DateTime.utc(2026, 9, 10),
      type: EventType.formal,
      status: status,
      courtLabel: 'Court',
      metadata: metadata,
    ),
    divisions: [
      EventDivision(
        id: DivisionId('91000000-0000-4000-8000-000000000002'),
        eventId: eventId,
        name: 'Open',
        format: format,
        metadata: metadata,
      ),
    ],
  );
}

final class _Writer implements EventSetupWriter {
  EventSetup? last;
  @override
  Future<RepositoryResult<EventSetupSaved>> save(
    EventSetup setup, {
    int? expectedVersion,
  }) async {
    last = setup;
    return RepositorySuccess(
      EventSetupSaved(
        setup: setup,
        disposition: EventMutationDisposition.pending,
      ),
    );
  }
}

final class _Ids implements EventSetupIdFactory {
  var next = 1;
  String _id() =>
      '90000000-0000-4000-8000-${(next++).toString().padLeft(12, '0')}';
  @override
  EventId eventId() => EventId(_id());
  @override
  DivisionId divisionId() => DivisionId(_id());
  @override
  SyncOperationId operationId() => SyncOperationId(_id());
}

final class _Clock implements EventSetupClock {
  const _Clock();
  @override
  DateTime nowUtc() => DateTime.utc(2026, 9, 1);
}
