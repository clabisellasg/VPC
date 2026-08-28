import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PublicHomePage extends StatelessWidget {
  const PublicHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.sports_tennis,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
                semanticLabel: 'Pickleball club',
              ),
              const SizedBox(height: 20),
              Text(
                'Community pickleball, one court at a time.',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Browse current, upcoming, and completed Volta Paddle Club events. No account is required.',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.go('/events'),
                icon: const Icon(Icons.event),
                label: const Text('Browse events'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
