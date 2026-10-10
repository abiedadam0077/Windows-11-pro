import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/app_strings.dart';

/// Bottom navigation shell for the three main areas of the app.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.child});

  final Widget child;

  static const _paths = ['/home/dashboard', '/home/sessions', '/home/settings'];

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final location = GoRouterState.of(context).matchedLocation;
    var index = _paths.indexWhere((p) => location.startsWith(p));
    if (index < 0) index = 0;
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: KeyedSubtree(key: ValueKey(index), child: child),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => context.go(_paths[i]),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.space_dashboard_outlined),
            selectedIcon: const Icon(Icons.space_dashboard_rounded),
            label: s.isArabic ? 'الرئيسية' : 'Home',
          ),
          NavigationDestination(
            icon: const Icon(Icons.history_rounded),
            selectedIcon: const Icon(Icons.manage_history_rounded),
            label: s.isArabic ? 'الجلسات' : 'Sessions',
          ),
          NavigationDestination(
            icon: const Icon(Icons.tune_rounded),
            selectedIcon: const Icon(Icons.settings_rounded),
            label: s.t('settings_title'),
          ),
        ],
      ),
    );
  }
}
