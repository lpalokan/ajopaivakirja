import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import '../models/route.dart' as route_model;
import '../providers/route_provider.dart';
import '../providers/trip_provider.dart';
import '../providers/settings_provider.dart';
import '../services/database_service.dart';
import '../services/decimal_input.dart';
import '../widgets/odometer_dialog.dart';
import '../widgets/active_trip_card.dart';
import '../widgets/location_autocomplete.dart';
import '../widgets/main_bottom_nav.dart';

class RouteManagementScreen extends ConsumerStatefulWidget {
  const RouteManagementScreen({super.key});

  @override
  ConsumerState<RouteManagementScreen> createState() =>
      _RouteManagementScreenState();
}

class _RouteManagementScreenState extends ConsumerState<RouteManagementScreen> {
  @override
  Widget build(BuildContext context) {
    final routes = ref.watch(routeProvider);
    final tripState = ref.watch(tripProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Reitit')),
      bottomNavigationBar: const MainBottomNav(selectedIndex: 1),
      body: Column(
        children: [
          if (tripState.activeLeg != null)
            ActiveTripCard(leg: tripState.activeLeg!),
          Expanded(
            child: routes.isEmpty
                ? GestureDetector(
                    onTap: () => _showRouteDialog(),
                    behavior: HitTestBehavior.opaque,
                    child: const Center(
                      child: Text(
                        'Ei reittejä. Lisää uusi napauttamalla tästä.',
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: routes.length + 1,
                    itemBuilder: (context, index) {
                      if (index == routes.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Center(
                            child: TextButton.icon(
                              onPressed: () => _showRouteDialog(),
                              icon: const Icon(Symbols.add),
                              label: const Text('Lisää uusi reitti'),
                            ),
                          ),
                        );
                      }
                      final route = routes[index];
                      final isDriving = tripState.activeLeg != null;
                      return Dismissible(
                        key: Key('route_${route.id}'),
                        direction: DismissDirection.horizontal,
                        confirmDismiss: (direction) async {
                          if (direction == DismissDirection.endToStart) {
                            return await _deleteRoute(route);
                          } else {
                            _showRouteDialog(route: route);
                            return false;
                          }
                        },
                        background: Container(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 20),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Symbols.edit, color: Colors.white),
                        ),
                        secondaryBackground: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.error,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Symbols.delete,
                            color: Colors.white,
                          ),
                        ),
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            onTap: isDriving
                                ? null
                                : () => _startDrivingFromRoute(route),
                            title: Text(route.name),
                            subtitle: Text(
                              '${route.startLocation} → ${route.endLocation} · '
                              '${route.distanceKm.toStringAsFixed(1)} km',
                            ),
                            trailing: const Icon(Symbols.play_arrow, size: 18),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showRouteDialog({route_model.Route? route}) async {
    final nameController = TextEditingController(text: route?.name);
    final startController = TextEditingController(text: route?.startLocation);
    final endController = TextEditingController(text: route?.endLocation);
    final distController = TextEditingController(
      text: route?.distanceKm.toString() ?? '',
    );
    final purposeController = TextEditingController(text: route?.lastPurpose);

    // Load known locations for autocomplete
    List<String> knownLocations = [];
    try {
      knownLocations = await DatabaseService.getUniqueLocations();
    } catch (_) {}

    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(route != null ? 'Muokkaa reittiä' : 'Uusi reitti'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Nimi',
                  hintText: 'Esim. Koti ↔ Toimisto',
                ),
              ),
              const SizedBox(height: 12),
              LocationAutocomplete(
                controller: startController,
                label: 'Lähtöpaikka',
                suggestions: knownLocations,
              ),
              const SizedBox(height: 12),
              LocationAutocomplete(
                controller: endController,
                label: 'Määränpää',
                suggestions: knownLocations,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: distController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Matkan pituus (km)',
                  suffixText: 'km',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: purposeController,
                decoration: const InputDecoration(
                  labelText: 'Tarkoitus (oletus)',
                  hintText: 'Esim. asiakastapaaminen',
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Peruuta'),
          ),
          FilledButton(
            onPressed: () {
              if (nameController.text.isEmpty ||
                  startController.text.isEmpty ||
                  endController.text.isEmpty ||
                  distController.text.isEmpty) {
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('Tallenna'),
          ),
        ],
      ),
    );

    if (result == true) {
      final now = DateTime.now();
      final dist = parseDecimal(distController.text);

      if (route != null) {
        await ref
            .read(routeProvider.notifier)
            .update(
              route.copyWith(
                name: nameController.text.trim(),
                startLocation: startController.text.trim(),
                endLocation: endController.text.trim(),
                distanceKm: dist ?? route.distanceKm,
                lastPurpose: purposeController.text.trim().isEmpty
                    ? null
                    : purposeController.text.trim(),
                updatedAt: now,
              ),
            );
      } else {
        await ref
            .read(routeProvider.notifier)
            .add(
              route_model.Route(
                name: nameController.text.trim(),
                startLocation: startController.text.trim(),
                endLocation: endController.text.trim(),
                distanceKm: dist ?? 0,
                lastPurpose: purposeController.text.trim().isEmpty
                    ? null
                    : purposeController.text.trim(),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
    }
  }

  Future<void> _startDrivingFromRoute(route_model.Route route) async {
    final settings = ref.read(settingsProvider);

    final lastLeg = await DatabaseService.getLastLeg();
    final initialOdometer = lastLeg?.endOdometer;

    if (!mounted) return;

    final result = await showOdometerDialog(
      context: context,
      title: 'Aloita ajo',
      subtitle:
          'Reitti: ${route.name}\n'
          '${route.startLocation} → ${route.endLocation}\n'
          'Matka: ${route.distanceKm.toStringAsFixed(1)} km',
      label: 'Matkamittari (km)',
      actionLabel: 'Aloita ajo',
      relatedField: 'Tarkoitus',
      initialPurpose: route.lastPurpose,
      initialValue: initialOdometer,
      showTime: true,
      initialTime: DateTime.now(),
      timeLabel: 'Alkamisaika',
      visionService: ref.read(odometerVisionServiceProvider),
    );

    if (result == null) return;

    await ref
        .read(tripProvider.notifier)
        .startTrip(
          startOdometer: result.odometer,
          startLocation: route.startLocation,
          route: route,
          purpose: result.purpose ?? '',
          driver: settings.driverName,
          startTime: result.time,
        );

    if (mounted) Navigator.of(context).pop();
  }

  Future<bool> _deleteRoute(route_model.Route route) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Poista reitti'),
        content: Text('Haluatko varmasti poistaa reitin "${route.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Peruuta'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Poista'),
          ),
        ],
      ),
    );

    if (confirm == true && route.id != null) {
      await ref.read(routeProvider.notifier).remove(route.id!);
      return true;
    }
    return false;
  }
}
