import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PublicAppShell extends StatelessWidget {
  const PublicAppShell({
    required this.child,
    required this.location,
    super.key,
  });

  final Widget child;
  final String location;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = location.startsWith('/organizer/players')
        ? 2
        : location.startsWith('/account') || location.startsWith('/organizer')
        ? 3
        : location.startsWith('/players')
        ? 2
        : location.startsWith('/events')
        ? 1
        : 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        return Scaffold(
          appBar: AppBar(title: const Text('Volta Paddle Club')),
          body: wide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: selectedIndex,
                      labelType: NavigationRailLabelType.all,
                      onDestinationSelected: (index) => _go(context, index),
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.home_outlined),
                          selectedIcon: Icon(Icons.home),
                          label: Text('Home'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.event_outlined),
                          selectedIcon: Icon(Icons.event),
                          label: Text('Events'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.people_outline),
                          selectedIcon: Icon(Icons.people),
                          label: Text('Players'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.account_circle_outlined),
                          selectedIcon: Icon(Icons.account_circle),
                          label: Text('Account'),
                        ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: child),
                  ],
                )
              : child,
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) => _go(context, index),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: 'Home',
                      tooltip: 'Public home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.event_outlined),
                      selectedIcon: Icon(Icons.event),
                      label: 'Events',
                      tooltip: 'Public events',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.people_outline),
                      selectedIcon: Icon(Icons.people),
                      label: 'Players',
                      tooltip: 'Community players',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.account_circle_outlined),
                      selectedIcon: Icon(Icons.account_circle),
                      label: 'Account',
                      tooltip: 'Account',
                    ),
                  ],
                ),
        );
      },
    );
  }

  void _go(BuildContext context, int index) {
    context.go(switch (index) {
      0 => '/',
      1 => '/events',
      2 => '/players',
      _ => '/account',
    });
  }
}
