import 'package:flutter/material.dart';

import '../app_state.dart';
import '../tts/tts_controller.dart';
import 'discover_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'notebook_screen.dart';
import 'player_sheet.dart';
import 'settings_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  void goTo(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(onGoLibrary: () => goTo(2)),
      const DiscoverScreen(),
      const LibraryScreen(),
      const NotebookScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _tab, children: pages)),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListenableBuilder(
            listenable: tts,
            builder: (context, _) => tts.hasBook ? const MiniPlayer() : const SizedBox.shrink(),
          ),
          ListenableBuilder(
            listenable: appState,
            builder: (context, _) => NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: goTo,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Trang chủ'),
                NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Khám phá'),
                NavigationDestination(icon: Icon(Icons.local_library_outlined), selectedIcon: Icon(Icons.local_library), label: 'Thư viện'),
                NavigationDestination(icon: Icon(Icons.edit_note_outlined), selectedIcon: Icon(Icons.edit_note), label: 'Sổ tay'),
                NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Cài đặt'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
