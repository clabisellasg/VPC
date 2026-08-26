import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vpc/src/app/app_router.dart';
import 'package:vpc/src/core/config/app_environment.dart';
import 'package:vpc/src/infrastructure/persistence/local/local_persistence_providers.dart';

class VpcApp extends ConsumerWidget {
  VpcApp({required this.environment, super.key})
    : router = createAppRouter(environment);

  final AppEnvironment environment;
  final GoRouter router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(localDatabaseProvider);
    return MaterialApp.router(
      title: 'Volta Paddle Club',
      theme: ThemeData(useMaterial3: true),
      routerConfig: router,
    );
  }
}
