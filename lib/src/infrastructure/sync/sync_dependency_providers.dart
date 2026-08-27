import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/sync/sync_contracts.dart';
import 'sync_primitives.dart';

final syncClockProvider = Provider<SyncClock>((ref) => const SystemSyncClock());

final syncIdFactoryProvider = Provider<SyncIdFactory>(
  (ref) => SecureSyncIdFactory(),
);

final syncJitterProvider = Provider<SyncJitter>((ref) => RandomSyncJitter());
