import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/accounts/account_models.dart';
import 'package:vpc/src/application/events/event_setup_models.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/events/event.dart';
import 'package:vpc/src/domain/events/event_division.dart';
import 'package:vpc/src/presentation/accounts/account_controller.dart';
import 'package:vpc/src/presentation/events/division_format_selector.dart';

import '../../domain/tournament/tournament_fixtures.dart';

void main() {
  for (final role in [
    AuthorizationState.guest,
    AuthorizationState.member,
    AuthorizationState.organizer,
  ]) {
    for (final width in [320.0, 1000.0]) {
      testWidgets('$role format boundary at width $width with enlarged text', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final division = EventDivision(
          id: fixtureDivision,
          eventId: fixtureEvent,
          name: 'Open',
          format: null,
          metadata: fixtureMetadata(),
        );
        final setup = EventSetup(
          event: Event(
            id: fixtureEvent,
            name: 'VPC Test',
            scheduledAt: DateTime.utc(2026, 9, 4),
            type: EventType.formal,
            status: EventStatus.registration,
            courtLabel: 'Sample Court',
            metadata: fixtureMetadata(),
          ),
          divisions: [division],
          readiness: {
            fixtureDivision: const DivisionTournamentReadiness(
              completeTeams: 0,
              activeMatches: 0,
            ),
          },
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              accountControllerProvider.overrideWithBuild(
                (ref, self) => AccountViewState(
                  phase: AccountPhase.content,
                  snapshot: AccountSnapshot(
                    profile: AccountProfile(
                      accountId: AccountId(fixtureId(90)),
                      displayName: 'VPC Sample',
                      metadata: fixtureMetadata(),
                    ),
                    authorization: role,
                    claim: null,
                  ),
                ),
              ),
            ],
            child: MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 1000),
                  textScaler: const TextScaler.linear(1.8),
                ),
                child: Scaffold(
                  body: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      DivisionFormatSelector(setup: setup, division: division),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Open — Not configured'), findsOneWidget);
        if (role == AuthorizationState.organizer) {
          final dropdown = tester
              .widget<DropdownButtonFormField<TournamentFormat>>(
                find.byType(DropdownButtonFormField<TournamentFormat>),
              );
          expect(dropdown, isNotNull);
          await tester.tap(
            find.byType(DropdownButtonFormField<TournamentFormat>),
          );
          await tester.pumpAndSettle();
          for (final format in TournamentFormat.values) {
            expect(find.text(tournamentFormatLabel(format)), findsWidgets);
          }
        } else {
          expect(
            find.byType(DropdownButtonFormField<TournamentFormat>),
            findsNothing,
          );
          expect(find.text('Save format'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
