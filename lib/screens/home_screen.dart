import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../models/route.dart' as model;
import '../models/trip_leg.dart';
import '../providers/route_provider.dart';
import '../providers/trip_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/odometer_dialog.dart';
import 'settings_screen.dart';
import 'route_management_screen.dart';
import 'trip_history_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ref.read(settingsProvider.notifier).load();
      ref.read(routeProvider.notifier).load();
      ref.read(tripProvider.notifier).load();

      final backgroundService = ref.read(backgroundServiceProvider);
      final tripNotifier = ref.read(tripProvider.notifier);

      await backgroundService.initialize();

      backgroundService.onArrived = () {
        final activeLeg = ref.read(tripProvider).activeLeg;
        if (activeLeg != null) {
          final expectedOdometer =
              activeLeg.startOdometer + activeLeg.kmDriven.toInt();
          showOdometerDialog(
            context: context,
            title: 'Olen perillä',
            subtitle: 'Kohde: ${activeLeg.endLocation ?? activeLeg.routeDescription}',
            label: 'Matkamittari perillä (km)',
            actionLabel: 'Lopeta ajo',
            initialValue: expectedOdometer,
            expectedHint: expectedOdometer,
          ).then((result) {
            if (result != null && context.mounted) {
              tripNotifier.stopDriving(result.odometer);
              backgroundService.onDrivingStopped();
            }
          });
        }
      };

      backgroundService.onStillDriving = () {
        backgroundService.onStillDrivingPressed();
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final routes = ref.watch(routeProvider);
    final tripState = ref.watch(tripProvider);
    final settings = ref.watch(settingsProvider);
    final recentRoutes = ref.read(routeProvider.notifier).getRecentRoutes();
    final tripNotifier = ref.read(tripProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kilometrikorvaus'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (tripState.activeLeg != null) ...[
            _buildActiveTripCard(tripState.activeLeg!, context),
            const SizedBox(height: 24),
          ],
          _buildRecentRoutes(
              recentRoutes, settings, tripNotifier, context),
          if (routes.isNotEmpty) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const RouteManagementScreen()),
                );
              },
              icon: const Icon(Icons.more_horiz),
              label: Text('Kaikki reitit (${routes.length})'),
            ),
          ],
          if (routes.isEmpty) ...[
            const SizedBox(height: 16),
            _buildEmptyState(context),
          ],
          const SizedBox(height: 24),
          if (tripState.todayLegs.isNotEmpty) _buildTodaySummary(tripState.todayLegs, context),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) =>
                        const TripHistoryScreen()),
              );
            },
            icon: const Icon(Icons.history),
            label: const Text('Historia'),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTripCard(TripLeg leg, BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final startTime = DateFormat('HH:mm').format(leg.startTime);
    final duration = DateTime.now().difference(leg.startTime);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final durationStr = '$hours h ${minutes.toString().padLeft(2, '0')} min';
    final expectedOdometer =
        leg.startOdometer + leg.kmDriven.toInt();

    return Card(
      color: colorScheme.primaryContainer,
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
                    Text(
                      'Ajo käynnissä',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      leg.routeDescription ?? '${leg.startLocation} → ${leg.endLocation}',
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
                final tripNotifier = ref.read(tripProvider.notifier);
                final backgroundService = ref.read(backgroundServiceProvider);
                final controller = TextEditingController(text: expectedOdometer.toString());
                final completer = Completer<int?>();
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) => PopScope(
                    canPop: false,
                    child: AlertDialog(
                      title: const Text('Olen perillä'),
                      content: TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Matkamittari perillä (km)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            completer.complete(null);
                          },
                          child: const Text('Peruuta'),
                        ),
                        FilledButton(
                          onPressed: () {
                            final v = int.tryParse(controller.text.trim());
                            if (v != null) {
                              Navigator.pop(ctx);
                              completer.complete(v);
                            }
                          },
                          child: const Text('Lopeta ajo'),
                        ),
                      ],
                    ),
                  ),
                );
                final endOdometer = await completer.future;
                if (endOdometer != null) {
                  await tripNotifier.stopDriving(endOdometer);
                  await backgroundService.onDrivingStopped();
                }
              },
              icon: const Icon(Icons.flag),
              label: const Text('Olen perillä'),
            ),
          ),
        ],
      ),
    ));
  }

  Widget _buildRecentRoutes(
    List<model.Route> recentRoutes,
    settings,
    TripNotifier tripNotifier,
    BuildContext context,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Viimeisimmät reitit',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...recentRoutes.map((route) => _buildRouteCard(
              route,
              tripNotifier,
              context,
            )),
      ],
    );
  }

  Widget _buildRouteCard(
    model.Route route,
    TripNotifier tripNotifier,
    BuildContext context,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(route.name,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    '${route.startLocation} → ${route.endLocation} · ${route.distanceKm.toStringAsFixed(1)} km',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: tripNotifier.isDriving
                  ? null
                  : () => _startDriving(route, context),
              child: const Text('Aloita'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startDriving(model.Route route, BuildContext context) async {
    final tripNotifier = ref.read(tripProvider.notifier);
    final routeNotifier = ref.read(routeProvider.notifier);
    final settings = ref.read(settingsProvider);

    final result = await showOdometerDialog(
      context: context,
      title: 'Aloita ajo',
      subtitle: 'Reitti: ${route.name}\n'
          '${route.startLocation} → ${route.endLocation}\n'
          'Matka: ${route.distanceKm.toStringAsFixed(1)} km',
      label: 'Matkamittari (km)',
      actionLabel: 'Aloita ajo',
      relatedField: 'Tarkoitus',
    );

    if (result != null) {
      final backgroundService = ref.read(backgroundServiceProvider);
      backgroundService.updateSettings(settings);
      final leg = await tripNotifier.startDriving(
        route: route,
        startOdometer: result.odometer,
        purpose: result.purpose ?? '',
        driver: settings.driverName,
      );
      await backgroundService.onDrivingStarted(leg);
      if (route.id != null &&
          result.purpose != null &&
          result.purpose!.isNotEmpty) {
        await routeNotifier.savePurpose(route.id!, result.purpose!);
      }
      await routeNotifier.markUsed(route.id!);
    }
  }

  Widget _buildTodaySummary(List<TripLeg> legs, BuildContext context) {
    final tripNotifier = ref.read(tripProvider.notifier);
    final summary = tripNotifier.daySummary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tänään (${legs.first.date})',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ...legs.map((leg) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.circle, size: 8),
                      const SizedBox(width: 8),
                      Text(
                        '${leg.startLocation} → ${leg.endLocation ?? '...'}  ',
                      ),
                      Text(
                        '${leg.kmDriven.toStringAsFixed(1)} km',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.primary),
                      ),
                      if (leg.dailyAllowance > 0)
                        Text(
                          '  (€${leg.dailyAllowance.toStringAsFixed(2)} pvr)',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                )),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Yht: ${summary.totalKm.toStringAsFixed(1)} km'),
                Text(
                    '€${summary.grandTotal.toStringAsFixed(2)}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Icon(Icons.add_road,
              size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text('Ei reittejä vielä',
              style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 8),
          Text(
            'Lisää reitti aloittaaksesi ajokirjanpidon.',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const RouteManagementScreen()),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('Lisää reitti'),
          ),
        ],
      ),
    );
  }
}
