import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/route.dart' as route_model;
import '../providers/route_provider.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reitit'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showRouteDialog(),
        child: const Icon(Icons.add),
      ),
      body: routes.isEmpty
          ? const Center(child: Text('Ei reittejä. Lisää uusi +-napista.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: routes.length,
              itemBuilder: (context, index) {
                final route = routes[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(route.name),
                    subtitle: Text(
                      '${route.startLocation} → ${route.endLocation} · '
                      '${route.distanceKm.toStringAsFixed(1)} km',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) {
                        if (action == 'edit') {
                          _showRouteDialog(route: route);
                        } else if (action == 'delete') {
                          _deleteRoute(route);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'edit', child: Text('Muokkaa')),
                        const PopupMenuItem(value: 'delete', child: Text('Poista')),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _showRouteDialog({route_model.Route? route}) async {
    final nameController = TextEditingController(text: route?.name);
    final startController = TextEditingController(text: route?.startLocation);
    final endController = TextEditingController(text: route?.endLocation);
    final distController =
        TextEditingController(text: route?.distanceKm.toString() ?? '');

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
              TextField(
                controller: startController,
                decoration: const InputDecoration(labelText: 'Lähtöpaikka'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: endController,
                decoration: const InputDecoration(labelText: 'Määränpää'),
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

  Future<void> _deleteRoute(route_model.Route route) async {
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
    }
  }
}
