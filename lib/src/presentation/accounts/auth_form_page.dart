import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/accounts/auth_models.dart';
import 'auth_controller.dart';

class AuthFormPage extends ConsumerStatefulWidget {
  const AuthFormPage({required this.registration, this.returnTo, super.key});

  final bool registration;
  final String? returnTo;

  @override
  ConsumerState<AuthFormPage> createState() => _AuthFormPageState();
}

class _AuthFormPageState extends ConsumerState<AuthFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _displayName = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    _displayName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final session = auth.session;
    if (session is AuthAwaitingEmailConfirmation) {
      return _CenteredCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mark_email_read_outlined, size: 48),
            const SizedBox(height: 16),
            Text(
              'Check your email',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Open the Volta Paddle Club confirmation link, then return to the app to continue.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => context.go('/account/sign-in'),
              child: const Text('Return to sign in'),
            ),
          ],
        ),
      );
    }
    if (session is AuthAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go(_safeReturnPath(widget.returnTo));
        }
      });
    }
    return _CenteredCard(
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.registration ? 'Create account' : 'Sign in',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Public events remain available without an account.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (widget.registration) ...[
                TextFormField(
                  controller: _displayName,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final length = value?.trim().length ?? 0;
                    if (length < 2 || length > 80) {
                      return 'Enter a display name between 2 and 80 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  return text.contains('@') && text.contains('.')
                      ? null
                      : 'Enter a valid email address.';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: _obscurePassword,
                textInputAction: widget.registration
                    ? TextInputAction.next
                    : TextInputAction.done,
                autofillHints: widget.registration
                    ? const [AutofillHints.newPassword]
                    : const [AutofillHints.password],
                onFieldSubmitted: (_) => widget.registration ? null : _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? 'Show password'
                        : 'Hide password',
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                  ),
                ),
                validator: (value) => (value?.length ?? 0) < 8
                    ? 'Use at least 8 characters.'
                    : null,
              ),
              if (widget.registration) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmation,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == _password.text
                      ? null
                      : 'Passwords do not match.',
                ),
              ],
              if (auth.message != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    auth.message!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: auth.isSubmitting ? null : _submit,
                child: auth.isSubmitting
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(widget.registration ? 'Create account' : 'Sign in'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: auth.isSubmitting
                    ? null
                    : () => context.go(
                        widget.registration
                            ? '/account/sign-in'
                            : '/account/register',
                      ),
                child: Text(
                  widget.registration
                      ? 'Already have an account? Sign in'
                      : 'Need an account? Register',
                ),
              ),
              if (!widget.registration)
                const Text(
                  'Password recovery is not available in this version.',
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final controller = ref.read(authControllerProvider.notifier);
    if (widget.registration) {
      await controller.register(
        email: _email.text,
        password: _password.text,
        displayName: _displayName.text,
      );
    } else {
      await controller.signIn(email: _email.text, password: _password.text);
    }
    _password.clear();
    _confirmation.clear();
  }
}

String _safeReturnPath(String? value) {
  if (value != null && value.startsWith('/') && !value.startsWith('//')) {
    return value;
  }
  return '/account';
}

class _CenteredCard extends StatelessWidget {
  const _CenteredCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Card(
          child: Padding(padding: const EdgeInsets.all(24), child: child),
        ),
      ),
    ),
  );
}
