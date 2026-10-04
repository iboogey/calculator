import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../routes/app_routes.dart';

/// The main tabs. Switching tabs replaces the stack so Back leaves the app.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.current});

  final String current;

  static const _tabs = [
    (Routes.home, Icons.home_outlined, Icons.home, 'الرئيسية'),
    (Routes.transactions, Icons.receipt_long_outlined, Icons.receipt_long, 'العمليات'),
    (Routes.budgets, Icons.donut_large_outlined, Icons.donut_large, 'الميزانية'),
    (Routes.settings, Icons.settings_outlined, Icons.settings, 'الإعدادات'),
  ];

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: _tabs.indexWhere((tab) => tab.$1 == current),
      onDestinationSelected: (index) {
        final route = _tabs[index].$1;
        if (route != current) Get.offAllNamed(route);
      },
      destinations: [
        for (final (_, icon, selectedIcon, label) in _tabs)
          NavigationDestination(
              icon: Icon(icon), selectedIcon: Icon(selectedIcon), label: label),
      ],
    );
  }
}
