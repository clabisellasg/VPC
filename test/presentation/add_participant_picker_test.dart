import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/accounts/account_models.dart';
import 'package:vpc/src/application/events/event_setup_contracts.dart';
import 'package:vpc/src/application/events/event_setup_models.dart';
import 'package:vpc/src/application/participation/participation_contracts.dart';
import 'package:vpc/src/application/participation/participation_models.dart';
import 'package:vpc/src/application/players/player_directory_models.dart';
import 'package:vpc/src/application/players/player_directory_reader.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/domain_failure.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/events/event_participant.dart';
import 'package:vpc/src/domain/events/participant_payment.dart';
import 'package:vpc/src/infrastructure/events/event_setup_providers.dart';
import 'package:vpc/src/infrastructure/participation/participation_providers.dart';
import 'package:vpc/src/infrastructure/players/player_directory_providers.dart';
import 'package:vpc/src/presentation/accounts/account_controller.dart';
import 'package:vpc/src/presentation/participation/add_participant_page.dart';

import '../domain/tournament/tournament_fixtures.dart';

class _Setup implements EventSetupStore {
  @override
  Future<RepositoryResult<EventSetup>> getSetup(EventId id) async =>
      const RepositoryFailure(
        PersistenceUnavailableFailure(
          message: 'No setup needed for picker test',
        ),
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Roster implements ParticipationStore {
  bool fail = false;
  @override
  Future<RepositoryResult<List<ParticipationRecord>>> listForEvent(
    EventId id,
  ) async => fail
      ? const RepositoryFailure(
          PersistenceUnavailableFailure(message: 'Offline roster failure'),
        )
      : RepositorySuccess([
          ParticipationRecord(
            participant: EventParticipant(
              id: EventParticipantId(fixtureId(30)),
              eventId: id,
              playerId: PlayerId(fixtureId(3)),
              checkInStatus: CheckInStatus.notPresent,
              metadata: fixtureMetadata(),
            ),
            payment: ParticipantPayment(
              id: ParticipantPaymentId(fixtureId(31)),
              eventParticipantId: EventParticipantId(fixtureId(30)),
              status: PaymentStatus.unpaid,
              metadata: fixtureMetadata(),
            ),
            playerDisplayName: 'VPC Registered',
            divisions: [],
          ),
        ]);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Players implements PlayerDirectoryReader {
  @override
  Future<RepositoryResult<PlayerDirectoryPage>> readPage(
    PlayerDirectoryQuery q,
  ) async => RepositorySuccess(
    PlayerDirectoryPage(
      entries: [
        PlayerDirectoryEntry(
          profile: PublicPlayerProfile(
            id: PlayerId(fixtureId(q.after == null ? 3 : 4)),
            displayName: q.after == null ? 'VPC Registered' : 'VPC Available',
            metadata: fixtureMetadata(),
          ),
        ),
      ],
      hasMore: q.after == null,
      origin: PlayerDirectoryOrigin.remote,
    ),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  for (final fail in [false, true]) {
    testWidgets(
      'registered players hidden; pagination and roster failure $fail',
      (tester) async {
        final roster = _Roster()..fail = fail;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              eventSetupStoreProvider.overrideWithValue(_Setup()),
              participationStoreProvider.overrideWithValue(roster),
              playerDirectoryReaderProvider.overrideWithValue(_Players()),
              accountControllerProvider.overrideWithBuild(
                (ref, self) => AccountViewState(
                  phase: AccountPhase.content,
                  snapshot: AccountSnapshot(
                    profile: AccountProfile(
                      accountId: AccountId(fixtureId(90)),
                      displayName: 'VPC Test',
                      metadata: fixtureMetadata(),
                    ),
                    authorization: AuthorizationState.organizer,
                    claim: null,
                  ),
                ),
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: AddParticipantPage(eventId: fixtureEvent.value),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(ListTile),
            matching: find.text('VPC Registered'),
          ),
          findsNothing,
        );
        if (fail) {
          expect(
            find.text('Unable to check the event roster. Please search again.'),
            findsOneWidget,
          );
          expect(find.text('Load more players'), findsNothing);
        } else {
          await tester.tap(find.text('Load more players'));
          await tester.pumpAndSettle();
          expect(find.text('VPC Available'), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(ListTile),
              matching: find.text('VPC Registered'),
            ),
            findsNothing,
          );
          await tester.enterText(find.byType(TextField), 'VPC Registered');
          await tester.tap(find.byTooltip('Search'));
          await tester.pumpAndSettle();
          expect(
            find.descendant(
              of: find.byType(ListTile),
              matching: find.text('VPC Registered'),
            ),
            findsNothing,
          );
          expect(find.text('VPC Available'), findsNothing);
        }
      },
    );
  }
}
