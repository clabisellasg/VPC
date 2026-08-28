import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/accounts/auth_models.dart';
import 'auth_controller.dart';

class AuthConfirmationPage extends ConsumerWidget {
  const AuthConfirmationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);
    final (icon, title, body) = switch (state.session) {
      AuthAuthenticated() => (
        Icons.check_circle_outline,
        'Email confirmed',
        'Your Volta Paddle Club account is ready.',
      ),
      AuthRecoverableFailure() => (
        Icons.link_off,
        'Confirmation could not be completed',
        'The link may be invalid or expired. Return to sign in and try again.',
      ),
      AuthUnconfigured() => (
        Icons.cloud_off_outlined,
        'Account services are not configured',
        'Use a configured build to confirm an account.',
      ),
      _ => (
        Icons.hourglass_top,
        'Confirming your account',
        'Please wait while the secure session is restored.',
      ),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 52),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(body, textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => context.go(
                      state.session is AuthAuthenticated
                          ? '/account'
                          : '/account/sign-in',
                    ),
                    child: Text(
                      state.session is AuthAuthenticated
                          ? 'View account'
                          : 'Return to sign in',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
