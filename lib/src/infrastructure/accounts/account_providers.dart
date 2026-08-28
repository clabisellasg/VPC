import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/accounts/auth_repository.dart';
import '../../application/accounts/player_claim_repository.dart';
import '../../core/supabase/supabase_client_provider.dart';
import 'supabase_auth_repository.dart';
import 'supabase_player_claim_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? const UnconfiguredAuthRepository()
      : SupabaseAuthRepository(OfficialSupabaseAuthGateway(client));
});

final playerClaimRepositoryProvider = Provider<PlayerClaimRepository?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabasePlayerClaimRepository(client);
});

final authRedirectProvider = Provider<String>((ref) {
  if (kIsWeb) {
    return Uri.base.resolve('/account/confirm').toString();
  }
  return 'com.voltapaddleclub.vpc://auth-callback/account/confirm';
});
