import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vpc/src/app/app_router.dart';
import 'package:vpc/src/core/config/app_environment.dart';
import 'package:vpc/src/core/platform/browser_online_status.dart';
import 'package:vpc/src/infrastructure/persistence/local/local_persistence_providers.dart';
import 'package:vpc/src/presentation/accounts/auth_controller.dart';
import 'package:vpc/src/presentation/accounts/account_controller.dart';
import 'package:vpc/src/presentation/players/player_directory_controller.dart';
import 'package:vpc/src/presentation/public_events/public_events_controller.dart';

class VpcApp extends ConsumerStatefulWidget {
  VpcApp({required this.environment, super.key}) : router = createAppRouter();

  final AppEnvironment environment;
  final GoRouter router;

  @override
  ConsumerState<VpcApp> createState() => _VpcAppState();
}

class _VpcAppState extends ConsumerState<VpcApp> {
  late final AppLifecycleListener _lifecycleListener;
  var _resumeRefreshGeneration = 0;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(onResume: _schedulePublicRefresh);
  }

  @override
  void dispose() {
    _resumeRefreshGeneration++;
    _lifecycleListener.dispose();
    widget.router.dispose();
    super.dispose();
  }

  void _schedulePublicRefresh() {
    if (!kIsWeb) return;
    final generation = ++_resumeRefreshGeneration;
    unawaited(_recoverPublicDataAfterResume(generation));
  }

  Future<void> _recoverPublicDataAfterResume(int generation) async {
    const delays = <Duration>[
      Duration(milliseconds: 900),
      Duration(seconds: 3),
      Duration(seconds: 6),
    ];
    for (final delay in delays) {
      await Future<void>.delayed(delay);
      if (!mounted || generation != _resumeRefreshGeneration) return;
      await Future.wait([
        ref.read(publicEventsControllerProvider.notifier).refresh(),
        ref.read(playerDirectoryControllerProvider.notifier).refresh(),
      ]);
      if (!mounted || generation != _resumeRefreshGeneration) return;
      final events = ref.read(publicEventsControllerProvider).phase;
      final players = ref.read(playerDirectoryControllerProvider).phase;
      if (events != PublicEventsPhase.error &&
          events != PublicEventsPhase.unconfigured &&
          players != PlayerDirectoryPhase.error &&
          players != PlayerDirectoryPhase.unconfigured) {
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(localDatabaseProvider);
    ref.watch(authControllerProvider);
    ref.watch(accountControllerProvider);
    final browserOnline = ref.watch(browserOnlineProvider).value ?? true;
    ref.listen(browserOnlineProvider, (previous, next) {
      if (previous?.value == false && next.value == true) {
        _schedulePublicRefresh();
      }
    });
    return MaterialApp.router(
      title: 'Volta Paddle Club',
      theme: ThemeData(useMaterial3: true),
      builder: (context, child) => Column(
        children: <Widget>[
          if (!browserOnline)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: SafeArea(
                bottom: false,
                child: Semantics(
                  liveRegion: true,
                  child: const SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Text(
                        'Offline — iPhone and Web changes require a connection. '
                        'Reconnect, then retry.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Expanded(child: child ?? const SizedBox.shrink()),
        ],
      ),
      routerConfig: widget.router,
    );
  }
}
