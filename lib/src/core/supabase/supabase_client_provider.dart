import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_configuration.dart';
import 'public_supabase_rest_client.dart';

/// Null when the app was intentionally started without Supabase Dart defines.
final supabaseClientProvider = Provider<SupabaseClient?>((ref) => null);

/// A session-free client for RLS-approved public reads.
///
/// Keeping this client separate prevents an expired or invalid restored Auth
/// session from making guest-readable events, players, and history unavailable.
final publicSupabaseClientProvider = Provider<SupabaseClient?>((ref) {
  final client = createPublicSupabaseClient(
    SupabaseConfiguration.fromEnvironment(),
  );
  if (client != null) {
    ref.onDispose(() => unawaited(client.dispose()));
  }
  return client;
});

/// Header-minimal public GET transport for browser compatibility.
final publicSupabaseRestClientProvider = Provider<PublicSupabaseRestClient?>((
  ref,
) {
  final configuration = SupabaseConfiguration.fromEnvironment();
  if (!configuration.isConfigured) return null;
  final client = PublicSupabaseRestClient.fromConfiguration(configuration);
  ref.onDispose(client.close);
  return client;
});

SupabaseClient? createPublicSupabaseClient(
  SupabaseConfiguration configuration,
) {
  if (!configuration.isConfigured) return null;
  return SupabaseClient(
    configuration.url!,
    configuration.publishableKey!,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
}
