import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vpc/src/core/config/app_environment.dart';
import 'package:vpc/src/presentation/bootstrap_page.dart';

GoRouter createAppRouter(AppEnvironment environment) {
  return GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => BootstrapPage(environment: environment),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
