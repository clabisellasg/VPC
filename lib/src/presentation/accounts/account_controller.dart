import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/accounts/account_models.dart';
import '../../application/accounts/auth_models.dart';
import '../../application/accounts/player_claim_repository.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import '../../domain/players/permanent_player.dart';
import '../../infrastructure/accounts/account_providers.dart';
import '../../infrastructure/sync/sync_providers.dart';
import '../../infrastructure/events/event_setup_providers.dart';
import 'auth_controller.dart';

enum AccountPhase { guest, loading, content, unavailable, unconfigured }

final class AccountViewState {
  const AccountViewState({
    required this.phase,
    this.snapshot,
    this.players = const [],
    this.pendingClaims = const [],
    this.isWorking = false,
    this.message,
  });

  final AccountPhase phase;
  final AccountSnapshot? snapshot;
  final List<PermanentPlayer> players;
  final List<PlayerClaim> pendingClaims;
  final bool isWorking;
  final String? message;

  AccountViewState copyWith({
    AccountPhase? phase,
    AccountSnapshot? snapshot,
    List<PermanentPlayer>? players,
    List<PlayerClaim>? pendingClaims,
    bool? isWorking,
    String? message,
    bool clearMessage = false,
  }) => AccountViewState(
    phase: phase ?? this.phase,
    snapshot: snapshot ?? this.snapshot,
    players: players ?? this.players,
    pendingClaims: pendingClaims ?? this.pendingClaims,
    isWorking: isWorking ?? this.isWorking,
    message: clearMessage ? null : message ?? this.message,
  );
}

final accountControllerProvider =
    NotifierProvider<AccountController, AccountViewState>(
      AccountController.new,
    );

final class AccountController extends Notifier<AccountViewState> {
  var _request = 0;
  var _disposed = false;
  final _random = Random.secure();

  @override
  AccountViewState build() {
    final auth = ref.watch(authControllerProvider).session;
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    if (auth is AuthUnconfigured) {
      ref.invalidate(syncRuntimeProvider);
      ref.invalidate(eventSetupRealtimeRuntimeProvider);
      return const AccountViewState(phase: AccountPhase.unconfigured);
    }
    if (auth is! AuthAuthenticated) {
      ref.invalidate(syncRuntimeProvider);
      ref.invalidate(eventSetupRealtimeRuntimeProvider);
      return const AccountViewState(phase: AccountPhase.guest);
    }
    unawaited(Future<void>(refresh));
    return const AccountViewState(phase: AccountPhase.loading);
  }

  Future<void> refresh() async {
    final repository = ref.read(playerClaimRepositoryProvider);
    if (repository == null) {
      state = const AccountViewState(phase: AccountPhase.unconfigured);
      return;
    }
    final request = ++_request;
    final result = await repository.loadCurrentAccount();
    if (_disposed || request != _request) {
      return;
    }
    result.when(
      success: (snapshot) {
        state = AccountViewState(
          phase: AccountPhase.content,
          snapshot: snapshot,
        );
        if (snapshot.authorization == AuthorizationState.organizer) {
          final runtime = ref.read(syncRuntimeProvider);
          if (runtime != null) {
            unawaited(runtime.start());
          }
          final eventSync = ref.read(eventSetupSynchronizerProvider);
          if (eventSync != null) {
            unawaited(eventSync.synchronize());
          }
          final eventRuntime = ref.read(eventSetupRealtimeRuntimeProvider);
          if (eventRuntime != null) {
            unawaited(eventRuntime.start());
          }
        } else {
          ref.invalidate(syncRuntimeProvider);
          ref.invalidate(eventSetupRealtimeRuntimeProvider);
        }
      },
      failure: (_) {
        ref.invalidate(syncRuntimeProvider);
        ref.invalidate(eventSetupRealtimeRuntimeProvider);
        state = const AccountViewState(
          phase: AccountPhase.unavailable,
          message: 'Account information is temporarily unavailable.',
        );
      },
    );
  }

  Future<void> searchPlayers(String query) async {
    final repository = ref.read(playerClaimRepositoryProvider);
    if (repository == null || state.isWorking) {
      return;
    }
    state = state.copyWith(isWorking: true, clearMessage: true);
    final result = await repository.searchEligiblePlayers(query);
    if (_disposed) {
      return;
    }
    result.when(
      success: (players) =>
          state = state.copyWith(players: players, isWorking: false),
      failure: (_) => state = state.copyWith(
        isWorking: false,
        message: 'Eligible players could not be loaded.',
      ),
    );
  }

  Future<bool> submitClaim(PlayerId playerId) => _claimMutation(
    (repository) => repository.submitClaim(
      claimId: PlayerClaimId(_uuidV4()),
      playerId: playerId,
    ),
  );

  Future<bool> cancelClaim(PlayerClaimId claimId) =>
      _claimMutation((repository) => repository.cancelPendingClaim(claimId));

  Future<void> loadPendingClaims() async {
    final repository = ref.read(playerClaimRepositoryProvider);
    if (repository == null || state.isWorking) {
      return;
    }
    state = state.copyWith(isWorking: true, clearMessage: true);
    final result = await repository.listPendingClaims();
    if (_disposed) {
      return;
    }
    result.when(
      success: (claims) =>
          state = state.copyWith(pendingClaims: claims, isWorking: false),
      failure: (_) => state = state.copyWith(
        isWorking: false,
        message: 'Pending claims could not be loaded.',
      ),
    );
  }

  Future<bool> approve(PlayerClaimId id) =>
      _review((repository) => repository.approveClaim(id));

  Future<bool> reject(PlayerClaimId id, {String? reason}) =>
      _review((repository) => repository.rejectClaim(id, reason: reason));

  Future<bool> _review(
    Future<RepositoryResult<PlayerClaim>> Function(
      PlayerClaimRepository repository,
    )
    action,
  ) async {
    final success = await _claimMutation(action, refreshAccount: false);
    if (success) {
      await loadPendingClaims();
    }
    return success;
  }

  Future<bool> _claimMutation(
    Future<RepositoryResult<PlayerClaim>> Function(
      PlayerClaimRepository repository,
    )
    action, {
    bool refreshAccount = true,
  }) async {
    final repository = ref.read(playerClaimRepositoryProvider);
    if (repository == null || state.isWorking) {
      return false;
    }
    state = state.copyWith(isWorking: true, clearMessage: true);
    final result = await action(repository);
    if (_disposed) {
      return false;
    }
    var succeeded = false;
    result.when(
      success: (_) {
        succeeded = true;
        state = state.copyWith(isWorking: false);
      },
      failure: (_) => state = state.copyWith(
        isWorking: false,
        message: 'The claim changed or could not be updated.',
      ),
    );
    if (succeeded && refreshAccount) {
      await refresh();
    }
    return succeeded;
  }

  String _uuidV4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
