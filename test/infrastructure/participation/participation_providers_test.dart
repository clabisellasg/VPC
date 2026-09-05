import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/participation/participation_contracts.dart';
import 'package:vpc/src/application/participation/participation_models.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/record_metadata.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/events/event_participant.dart';
import 'package:vpc/src/domain/events/participant_payment.dart';
import 'package:vpc/src/infrastructure/participation/participation_providers.dart';
import 'package:vpc/src/infrastructure/participation/participation_writers.dart';
import 'package:vpc/src/infrastructure/persistence/local/local_persistence_providers.dart';

void main() {
  test('Web participation composition never initializes SQLite', () {
    var databaseFactoryCalls = 0;
    LocalPersistencePlatform? requestedPlatform;
    final container = ProviderContainer(
      overrides: [
        localPersistencePlatformProvider.overrideWithValue(
          LocalPersistencePlatform.web,
        ),
        localDatabaseFactoryProvider.overrideWithValue((platform) {
          databaseFactoryCalls++;
          requestedPlatform = platform;
          return null;
        }),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(driftParticipationStoreProvider), isNull);
    expect(
      container.read(participationWriterProvider),
      isA<UnavailableParticipationWriter>(),
    );
    expect(container.read(participationSynchronizerProvider), isNull);
    expect(container.read(participationRealtimeRuntimeProvider), isNull);
    expect(databaseFactoryCalls, 1);
    expect(requestedPlatform, LocalPersistencePlatform.web);
  });

  test('Web roster follows bounded participation pages', () async {
    final remote = _PagedRemote();
    final container = ProviderContainer(
      overrides: [
        localPersistencePlatformProvider.overrideWithValue(
          LocalPersistencePlatform.web,
        ),
        participationRemoteProvider.overrideWithValue(remote),
      ],
    );
    addTearDown(container.dispose);

    final result = await container
        .read(participationStoreProvider)!
        .listForEvent(EventId(_targetEventId));

    expect(result, isA<RepositorySuccess<List<ParticipationRecord>>>());
    expect(
      (result as RepositorySuccess<List<ParticipationRecord>>)
          .value
          .single
          .participant
          .eventId
          .value,
      _targetEventId,
    );
    expect(remote.pullCount, 2);
  });
}

final class _PagedRemote implements ParticipationRemoteGateway {
  var pullCount = 0;

  @override
  Future<ParticipationRemoteResult> apply(
    ParticipationOperation operation,
  ) async => throw UnimplementedError();

  @override
  Future<RepositoryResult<ParticipationPullPage>> pull({
    DateTime? afterUpdatedAt,
    EventParticipantId? afterId,
    int limit = 50,
  }) async {
    pullCount++;
    return RepositorySuccess(
      ParticipationPullPage(
        records: [
          _record(pullCount, pullCount == 1 ? _olderEventId : _targetEventId),
        ],
        hasMore: pullCount == 1,
      ),
    );
  }
}

ParticipationRecord _record(int sequence, String eventId) {
  final suffix = sequence.toString().padLeft(12, '0');
  final participantId = EventParticipantId('10000000-0000-4000-8000-$suffix');
  final metadata = RecordMetadata(
    createdAt: DateTime.utc(2026, 9, 5, 1, sequence),
    updatedAt: DateTime.utc(2026, 9, 5, 1, sequence),
    recordVersion: 0,
  );
  return ParticipationRecord(
    participant: EventParticipant(
      id: participantId,
      eventId: EventId(eventId),
      playerId: PlayerId('20000000-0000-4000-8000-$suffix'),
      checkInStatus: CheckInStatus.checkedIn,
      metadata: metadata,
    ),
    payment: ParticipantPayment(
      id: ParticipantPaymentId('30000000-0000-4000-8000-$suffix'),
      eventParticipantId: participantId,
      status: PaymentStatus.unpaid,
      metadata: metadata,
    ),
    playerDisplayName: 'VPC Sample $sequence',
    divisions: const [],
  );
}

const _olderEventId = '40000000-0000-4000-8000-000000000001';
const _targetEventId = '40000000-0000-4000-8000-000000000002';
