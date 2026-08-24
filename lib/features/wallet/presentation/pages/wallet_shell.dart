import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class WalletScaffold extends StatelessWidget {
  const WalletScaffold({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const List<_NavItem> _items = [
    _NavItem(
      icon: Icons.wallet_outlined,
      selectedIcon: Icons.wallet,
      label: '卡包',
    ),
    _NavItem(
      icon: Icons.notifications_none_outlined,
      selectedIcon: Icons.notifications,
      label: '通知',
    ),
    _NavItem(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: '设置',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (index) =>
            shell.goBranch(index, initialLocation: index == shell.currentIndex),
        destinations: [
          for (final item in _items)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon),
              label: item.label,
            ),
        ],
      ),
    );
  }
}

final class _NavItem {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
