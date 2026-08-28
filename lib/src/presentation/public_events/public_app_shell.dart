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
    final selectedIndex = location.startsWith('/events') ? 1 : 0;
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
                  ],
                ),
        );
      },
    );
  }

  void _go(BuildContext context, int index) {
    context.go(index == 0 ? '/' : '/events');
  }
}
