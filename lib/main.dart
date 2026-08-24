import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vpc/src/app/app.dart';
import 'package:vpc/src/core/config/app_environment.dart';

void main() {
  final environment = AppEnvironment.resolve();

  runApp(ProviderScope(child: VpcApp(environment: environment)));
}
