import 'package:flutter/material.dart';

import '../main.dart';
import 'home/class_selection_page.dart';
import 'history/history_page.dart';
import 'analytics/dashboard_page.dart';
import 'demo/demo_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    ClassSelectionPage(),
    HistoryPage(),
    DashboardPage(),
  ];

  final List<String> _titles = const [
    'Detect',
    'History',
    'Analytics',
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = MyApp.isDarkMode(context);
    
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).cardColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0.5,
        title: Text(
          _titles[_currentIndex],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => MyApp.toggleTheme(context),
            tooltip: isDark ? 'Light Mode' : 'Dark Mode',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'demo') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DemoPage()),
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'demo', child: Text('Demo Mode')),
            ],
          ),
        ],
      ),
      body: _pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.camera_alt_outlined),
            selectedIcon: Icon(Icons.camera_alt),
            label: 'Detect',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Analytics',
          ),
        ],
      ),
    );
  }
}
