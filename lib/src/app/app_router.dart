import 'package:flutter/material.dart';
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

GoRouter createAppRouter() {
  return GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      ShellRoute(
        builder: (context, state, child) =>
            PublicAppShell(location: state.uri.path, child: child),
        routes: [
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
