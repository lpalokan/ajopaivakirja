import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../models/route.dart' as route_model;
import '../models/trip_leg.dart';
import '../providers/route_provider.dart';
import '../providers/trip_provider.dart';
import '../providers/settings_provider.dart';
import '../services/database_service.dart';
import '../widgets/odometer_dialog.dart';

class RouteManagementScreen extends ConsumerStatefulWidget {
  const RouteManagementScreen({super.key});

  @override
  ConsumerState<RouteManagementScreen> createState() =>
      _RouteManagementScreenState();
}

class _RouteManagementScreenState
    extends ConsumerState<RouteManagementScreen> {
  @override
  Widget build(BuildContext context) {
    final routes = ref.watch(routeProvider);
    final tripState = ref.watch(tripProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Reitit')),
      body: Column(
        children: [
          if (tripState.activeLeg != null)
            _buildActiveTripCard(tripState.activeLeg!, context),
          Expanded(
            child: routes.isEmpty
                ? GestureDetector(
                    onTap: () => _showRouteDialog(),
                    behavior: HitTestBehavior.opaque,
                    child: const Center(
                      child: Text('Ei reittejä. Lisää uusi napauttamalla tästä.'),
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
                              icon: const Icon(Icons.add),
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
                          child: const Icon(Icons.edit, color: Colors.white),
                        ),
                        secondaryBackground: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.error,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            onTap: isDriving ? null : () => _startDrivingFromRoute(route),
                            title: Text(route.name),
                            subtitle: Text(
                              '${route.startLocation} → ${route.endLocation} · '
                              '${route.distanceKm.toStringAsFixed(1)} km',
                            ),
                            trailing: const Icon(Icons.play_arrow, size: 18),
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

  Widget _buildActiveTripCard(TripLeg leg, BuildContext context) {
    final tripNotifier = ref.read(tripProvider.notifier);
    final backgroundService = ref.read(backgroundServiceProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final startTime = DateFormat('HH:mm').format(leg.startTime);
    final duration = DateTime.now().difference(leg.startTime);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final durationStr = '$hours h ${minutes.toString().padLeft(2, '0')} min';
    final expectedOdometer = leg.startOdometer + leg.kmDriven.toInt();

    return Card(
      color: colorScheme.primaryContainer,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.directions_car, color: colorScheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ajo käynnissä',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        leg.routeDescription ??
                            '${leg.startLocation} → ${leg.endLocation}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Lähtö: $startTime'),
                Text('Kesto: $durationStr'),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Mittari lähtiessä: ${leg.startOdometer} km'),
                Text('Arvioitu perillä: $expectedOdometer km'),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  final result = await showOdometerDialog(
                    context: context,
                    title: 'Olen perillä',
                    subtitle: 'Kohde: ${leg.endLocation ?? leg.routeDescription}',
                    label: 'Matkamittari perillä (km)',
                    actionLabel: 'Lopeta ajo',
                    initialValue: expectedOdometer,
                    expectedHint: expectedOdometer,
                  );
                  if (result != null) {
                    await tripNotifier.stopDriving(result.odometer);
                    await backgroundService.onDrivingStopped();
                  }
                },
                icon: const Icon(Icons.flag),
                label: const Text('Olen perillä'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRouteDialog({route_model.Route? route}) async {
    final nameController = TextEditingController(text: route?.name);
    final startController = TextEditingController(text: route?.startLocation);
    final endController = TextEditingController(text: route?.endLocation);
    final distController =
        TextEditingController(text: route?.distanceKm.toString() ?? '');

    // Load known locations for autocomplete
    List<String> knownLocations = [];
    try {
      knownLocations = await DatabaseService.getUniqueLocations();
    } catch (_) {}

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
              _LocationField(
                controller: startController,
                label: 'Lähtöpaikka',
                suggestions: knownLocations,
              ),
              const SizedBox(height: 12),
              _LocationField(
                controller: endController,
                label: 'Määränpää',
                suggestions: knownLocations,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: distController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Matkan pituus (km)',
                  suffixText: 'km',
                ),
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
      final dist = double.tryParse(
          distController.text.replaceAll(',', '.'));

      if (route != null) {
        await ref.read(routeProvider.notifier).update(
              route.copyWith(
                name: nameController.text.trim(),
                startLocation: startController.text.trim(),
                endLocation: endController.text.trim(),
                distanceKm: dist ?? route.distanceKm,
                updatedAt: now,
              ),
            );
      } else {
        await ref.read(routeProvider.notifier).add(
              route_model.Route(
                name: nameController.text.trim(),
                startLocation: startController.text.trim(),
                endLocation: endController.text.trim(),
                distanceKm: dist ?? 0,
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
    }
  }

  Future<void> _startDrivingFromRoute(route_model.Route route) async {
    final tripNotifier = ref.read(tripProvider.notifier);
    final settings = ref.read(settingsProvider);
    final backgroundService = ref.read(backgroundServiceProvider);
    final routeNotifier = ref.read(routeProvider.notifier);

    final lastLeg = await DatabaseService.getLastLeg();
    final initialOdometer = lastLeg?.endOdometer;

    if (!mounted) return;

    final result = await showOdometerDialog(
      context: context,
      title: 'Aloita ajo',
      subtitle: 'Reitti: ${route.name}\n'
          '${route.startLocation} → ${route.endLocation}\n'
          'Matka: ${route.distanceKm.toStringAsFixed(1)} km',
      label: 'Matkamittari (km)',
      actionLabel: 'Aloita ajo',
      relatedField: 'Tarkoitus',
      initialValue: initialOdometer,
    );

    if (result == null) return;

    backgroundService.updateSettings(settings);
    final leg = await tripNotifier.startDriving(
      route: route,
      startOdometer: result.odometer,
      purpose: result.purpose ?? '',
      driver: settings.driverName,
    );
    await backgroundService.onDrivingStarted(leg);
    if (route.id != null && result.purpose != null && result.purpose!.isNotEmpty) {
      await routeNotifier.savePurpose(route.id!, result.purpose!);
    }
    await routeNotifier.markUsed(route.id!);

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

class _LocationField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final List<String> suggestions;

  const _LocationField({
    required this.controller,
    required this.label,
    required this.suggestions,
  });

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      optionsBuilder: (textEditingValue) {
        final text = textEditingValue.text.toLowerCase();
        if (text.isEmpty) return suggestions;
        return suggestions.where((s) => s.toLowerCase().contains(text));
      },
      onSelected: (value) {
        controller.text = value;
        controller.selection = TextSelection.fromPosition(
          TextPosition(offset: value.length),
        );
      },
      fieldViewBuilder: (context, autocompleteCtrl, focusNode, onSubmitted) {
        autocompleteCtrl.text = controller.text;
        return TextField(
          controller: autocompleteCtrl,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            suffixIcon: GestureDetector(
              onTap: () => focusNode.requestFocus(),
              child: const Icon(Icons.arrow_drop_down),
            ),
          ),
          onChanged: (v) {
            controller.text = v;
          },
        );
      },
    );
  }
}
