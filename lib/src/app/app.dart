import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vpc/src/app/app_router.dart';
import 'package:vpc/src/core/config/app_environment.dart';

class VpcApp extends StatelessWidget {
  VpcApp({required this.environment, super.key})
    : router = createAppRouter(environment);

  final AppEnvironment environment;
  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Volta Paddle Club',
      theme: ThemeData(useMaterial3: true),
      routerConfig: router,
    );
  }
}
