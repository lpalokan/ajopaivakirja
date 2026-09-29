import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

import '../screens/route_management_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/trip_history_screen.dart';

/// Bottom NavigationBar shared by the four primary destinations.
///
/// Tapping a destination pops back to the home route and (if the target
/// isn't home) pushes the destination on top. This keeps the Navigator
/// stack a single push deep regardless of how the user moves between
/// tabs, so the AppBar back button on every sub-screen always returns to
/// home.
class MainBottomNav extends StatelessWidget {
  final int selectedIndex;

  const MainBottomNav({super.key, required this.selectedIndex});

  void _navigate(BuildContext context, int target) {
    if (target == selectedIndex) return;
    final navigator = Navigator.of(context);
    navigator.popUntil((r) => r.isFirst);
    if (target == 0) return;
    final Widget screen;
    switch (target) {
      case 1:
        screen = const RouteManagementScreen();
      case 2:
        screen = const TripHistoryScreen();
      case 3:
        screen = const SettingsScreen();
      default:
        return;
    }
    navigator.push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: (i) => _navigate(context, i),
      destinations: const [
        NavigationDestination(icon: Icon(Symbols.home), label: 'Etusivu'),
        NavigationDestination(
          icon: Icon(Symbols.alt_route),
          label: 'Reitit',
        ),
        NavigationDestination(
          icon: Icon(Icons.history),
          label: 'Historia',
        ),
        NavigationDestination(
          icon: Icon(Symbols.settings),
          label: 'Asetukset',
        ),
      ],
    );
  }
}
