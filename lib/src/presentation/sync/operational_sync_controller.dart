import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/sync/operational_sync.dart';
import '../../infrastructure/sync/operational_sync_providers.dart';

final operationalSyncControllerProvider =
    AsyncNotifierProvider<OperationalSyncController, OperationalSyncSnapshot>(
      OperationalSyncController.new,
    );

final class OperationalSyncController
    extends AsyncNotifier<OperationalSyncSnapshot> {
  @override
  Future<OperationalSyncSnapshot> build() => _load();

  Future<OperationalSyncSnapshot> _load() async {
    final store = ref.read(operationalSyncStoreProvider);
    return store == null ? const OperationalSyncSnapshot() : store.snapshot();
  }

  Future<void> refresh({bool synchronize = false}) async {
    final current = state.asData?.value;
    state = AsyncData(
      OperationalSyncSnapshot(
        items: current?.items ?? const [],
        lastSuccessfulSync: current?.lastSuccessfulSync,
        isSynchronizing: synchronize,
      ),
    );
    try {
      if (synchronize) {
        await ref.read(operationalSyncCoordinatorProvider)?.retryNow();
      }
      state = AsyncData(await _load());
    } catch (_) {
      state = AsyncData(
        OperationalSyncSnapshot(
          items: (await _load()).items,
          lastSuccessfulSync: current?.lastSuccessfulSync,
          isOffline: true,
        ),
      );
    }
  }

  Future<void> useCloud(String operationId) async {
    await ref
        .read(operationalSyncCoordinatorProvider)
        ?.useCloudVersion(operationId);
    state = AsyncData(await _load());
  }

  Future<void> reapply(String operationId) async {
    final replacement = _uuidV4();
    await ref
        .read(operationalSyncCoordinatorProvider)
        ?.reapplyLocalChange(operationId, replacement);
    state = AsyncData(await _load());
  }

  String _uuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
