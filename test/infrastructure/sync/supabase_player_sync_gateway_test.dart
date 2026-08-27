import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vpc/src/application/sync/sync_models.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/record_metadata.dart';
import 'package:vpc/src/domain/players/permanent_player.dart';
import 'package:vpc/src/infrastructure/sync/supabase_player_sync_gateway.dart';

void main() {
  test(
    'unconfigured session blocks upload and pull without a network call',
    () async {
      final client = SupabaseClient('https://example.invalid', '');
      final gateway = SupabasePlayerSyncGateway(client);
      final player = PermanentPlayer(
        id: PlayerId('90000000-0000-4000-8000-000000000001'),
        displayName: 'Test Player',
        metadata: RecordMetadata(
          createdAt: DateTime.utc(2026, 8, 28),
          updatedAt: DateTime.utc(2026, 8, 28),
          recordVersion: 0,
        ),
      );
      final operation = SyncOperation(
        id: SyncOperationId('90000000-0000-4000-8000-000000000002'),
        entityType: SyncEntityType.player,
        entityId: player.id,
        kind: SyncOperationKind.upsert,
        payload: PlayerSyncPayload.fromPlayer(player),
        createdAt: DateTime.utc(2026, 8, 28),
        attemptCount: 0,
        nextEligibleAt: DateTime.utc(2026, 8, 28),
        status: SyncOperationStatus.pending,
      );

      final apply = await gateway.applyPlayerOperation(operation);
      final pull = await gateway.pullPlayers(after: null, limit: 10);

      expect(apply, isA<RemoteApplyFailure>());
      expect(
        (apply as RemoteApplyFailure).kind,
        SyncFailureKind.authorizationBlocked,
      );
      expect(pull, isA<RemotePullFailure>());
      expect(
        (pull as RemotePullFailure).kind,
        SyncFailureKind.authorizationBlocked,
      );
      expect(apply.safeMessage, isNot(contains('Bearer')));
      await client.dispose();
    },
  );
}
