import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vpc/src/app/app.dart';
import 'package:vpc/src/core/config/app_environment.dart';
import 'package:vpc/src/core/config/supabase_configuration.dart';
import 'package:vpc/src/core/supabase/supabase_client_provider.dart';
import 'package:vpc/src/core/supabase/supabase_initializer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final environment = AppEnvironment.resolve();
  final supabaseConfiguration = SupabaseConfiguration.fromEnvironment();
  final supabaseClient = await initializeSupabaseIfConfigured(
    supabaseConfiguration,
  );

  runApp(
    ProviderScope(
      overrides: [supabaseClientProvider.overrideWithValue(supabaseClient)],
      child: VpcApp(environment: environment),
    ),
  );
}
