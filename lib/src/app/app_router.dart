import 'package:flutter/material.dart';

import '../presentation/tournament/single_elimination_page.dart';
import '../presentation/tournament/round_robin_page.dart';

import 'package:go_router/go_router.dart';
import 'package:vpc/src/presentation/public_events/public_app_shell.dart';
import 'package:vpc/src/presentation/public_events/public_event_details_page.dart';
import 'package:vpc/src/presentation/public_events/public_events_page.dart';
import 'package:vpc/src/presentation/public_events/public_home_page.dart';
import 'package:vpc/src/presentation/accounts/account_page.dart';
import 'package:vpc/src/presentation/accounts/auth_confirmation_page.dart';
import 'package:vpc/src/presentation/accounts/auth_form_page.dart';
import 'package:vpc/src/presentation/accounts/organizer_claims_page.dart';
import 'package:vpc/src/presentation/accounts/player_claim_page.dart';
import 'package:vpc/src/presentation/players/organizer_player_creation_page.dart';
import 'package:vpc/src/presentation/players/public_player_directory_page.dart';
import 'package:vpc/src/presentation/players/public_player_profile_page.dart';
import 'package:vpc/src/presentation/players/organizer_player_skill_page.dart';
import 'package:vpc/src/presentation/teams/organizer_team_formation_page.dart';
import 'package:vpc/src/presentation/events/organizer_events_page.dart';
import 'package:vpc/src/presentation/events/organizer_event_setup_page.dart';
import 'package:vpc/src/presentation/participation/add_participant_page.dart';
import 'package:vpc/src/presentation/participation/organizer_participants_page.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';

GoRouter createAppRouter() {
  // Organizer drill-downs use push so Android system back returns through the
  // account stack. Reflect those imperative routes in the Web URL as well so
  // refresh and browser back/forward preserve the visible page.
  GoRouter.optionURLReflectsImperativeAPIs = true;
  return GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      ShellRoute(
        builder: (context, state, child) =>
            PublicAppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/events/:eventId/divisions/:divisionId/bracket',
            builder: (context, state) => SingleEliminationPage(
              eventId: state.pathParameters['eventId']!,
              divisionId: state.pathParameters['divisionId']!,
            ),
          ),
          GoRoute(
            path: '/organizer/events/:eventId/divisions/:divisionId/generate',
            builder: (context, state) => SingleEliminationPage(
              eventId: state.pathParameters['eventId']!,
              divisionId: state.pathParameters['divisionId']!,
              organizerRoute: true,
            ),
          ),
          GoRoute(
            path: '/events/:eventId/divisions/:divisionId/round-robin',
            builder: (context, state) => RoundRobinPage(
              eventId: state.pathParameters['eventId']!,
              divisionId: state.pathParameters['divisionId']!,
            ),
          ),
          GoRoute(
            path: '/organizer/events/:eventId/divisions/:divisionId/round-robin/generate',
            builder: (context, state) => RoundRobinPage(
              eventId: state.pathParameters['eventId']!,
              divisionId: state.pathParameters['divisionId']!,
              organizerRoute: true,
            ),
          ),
          GoRoute(
            path: '/',
            builder: (context, state) => const PublicHomePage(),
          ),
          GoRoute(
            path: '/events',
            builder: (context, state) => const PublicEventsPage(),
            routes: [
              GoRoute(
                path: ':eventId',
                builder: (context, state) => PublicEventDetailsPage(
                  eventId: state.pathParameters['eventId'] ?? '',
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/account',
            builder: (context, state) => const AccountPage(),
            routes: [
              GoRoute(
                path: 'sign-in',
                builder: (context, state) => AuthFormPage(
                  registration: false,
                  returnTo: state.uri.queryParameters['from'],
                ),
              ),
              GoRoute(
                path: 'register',
                builder: (context, state) =>
                    const AuthFormPage(registration: true),
              ),
              GoRoute(
                path: 'confirm',
                builder: (context, state) => const AuthConfirmationPage(),
              ),
              GoRoute(
                path: 'claim',
                builder: (context, state) => const PlayerClaimPage(),
              ),
            ],
          ),
          GoRoute(
            path: '/players',
            builder: (context, state) => const PublicPlayerDirectoryPage(),
            routes: [
              GoRoute(
                path: ':playerId',
                builder: (context, state) => PublicPlayerProfilePage(
                  playerId: state.pathParameters['playerId'] ?? '',
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/organizer/claims',
            builder: (context, state) => const OrganizerClaimsPage(),
          ),
          GoRoute(
            path: '/organizer/players/new',
            builder: (context, state) => const OrganizerPlayerCreationPage(),
          ),
          GoRoute(
            path: '/organizer/players/:playerId/skill',
            builder: (context, state) => OrganizerPlayerSkillPage(
              playerId: state.pathParameters['playerId'] ?? '',
            ),
          ),
          GoRoute(
            path: '/organizer/events',
            builder: (context, state) => const OrganizerEventsPage(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => OrganizerEventSetupPage(
                  type: state.uri.queryParameters['type'] == 'formal'
                      ? EventType.formal
                      : EventType.casual,
                ),
              ),
              GoRoute(
                path: ':eventId/setup',
                builder: (context, state) => OrganizerEventSetupPage(
                  type: EventType.formal,
                  eventId: state.pathParameters['eventId'],
                ),
              ),
              GoRoute(
                path: ':eventId/participants',
                builder: (context, state) => OrganizerParticipantsPage(
                  eventId: state.pathParameters['eventId'] ?? '',
                ),
                routes: [
                  GoRoute(
                    path: 'add',
                    builder: (context, state) => AddParticipantPage(
                      eventId: state.pathParameters['eventId'] ?? '',
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: ':eventId/divisions/:divisionId/teams',
                builder: (context, state) => OrganizerTeamFormationPage(
                  eventId: state.pathParameters['eventId'] ?? '',
                  divisionId: state.pathParameters['divisionId'] ?? '',
                ),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) =>
        _UnknownRoutePage(location: state.uri.toString()),
  );
}

class _UnknownRoutePage extends StatelessWidget {
  const _UnknownRoutePage({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Page not found',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  location,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Return home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
