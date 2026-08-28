import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vpc/src/presentation/public_events/public_app_shell.dart';
import 'package:vpc/src/presentation/public_events/public_event_details_page.dart';
import 'package:vpc/src/presentation/public_events/public_events_page.dart';
import 'package:vpc/src/presentation/public_events/public_home_page.dart';

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
