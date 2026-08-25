import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_configuration.dart';

abstract interface class SupabaseInitializer {
  Future<SupabaseClient> initialize(SupabaseConfiguration configuration);
}

final class OfficialSupabaseInitializer implements SupabaseInitializer {
  const OfficialSupabaseInitializer();

  @override
  Future<SupabaseClient> initialize(SupabaseConfiguration configuration) async {
    final initialized = await Supabase.initialize(
      url: configuration.url!,
      publishableKey: configuration.publishableKey!,
    );
    return initialized.client;
  }
}

Future<SupabaseClient?> initializeSupabaseIfConfigured(
  SupabaseConfiguration configuration, {
  SupabaseInitializer initializer = const OfficialSupabaseInitializer(),
}) async {
  if (!configuration.isConfigured) {
    return null;
  }
  return initializer.initialize(configuration);
}
