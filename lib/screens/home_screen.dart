import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import '../models/route.dart' as model;
import '../models/trip_leg.dart';
import '../providers/route_provider.dart';
import '../providers/trip_provider.dart';
import '../providers/settings_provider.dart';
import '../services/database_service.dart';
import '../services/log_service.dart';
import '../widgets/odometer_dialog.dart';
import '../widgets/active_trip_card.dart';
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
      await ref.read(settingsProvider.notifier).load();
      await ref.read(routeProvider.notifier).load();
      final tripNotif2 = ref.read(tripProvider.notifier);
      await tripNotif2.loadKmRates();
      tripNotif2.load();

      final settings = ref.read(settingsProvider);
      await LogService().init(enabled: settings.debugLogging);

      // Seed debug routes
      if (kDebugMode) {
        final routes = ref.read(routeProvider);
        if (routes.isEmpty) {
          final routeNotifier = ref.read(routeProvider.notifier);
          final now = DateTime.now();
          await routeNotifier.add(model.Route(
            name: 'Töihin',
            startLocation: 'Koti',
            endLocation: 'Työ',
            distanceKm: 54,
            createdAt: now,
            updatedAt: now,
          ));
          await routeNotifier.add(model.Route(
            name: 'Kotiin',
            startLocation: 'Työ',
            endLocation: 'Koti',
            distanceKm: 54,
            createdAt: now,
            updatedAt: now,
          ));
          LogService().info('App: seeded debug routes (Töihin, Kotiin)');
        }
      }

      final backgroundService = ref.read(backgroundServiceProvider);
      final tripNotif = ref.read(tripProvider.notifier);

      await backgroundService.initialize();

      final notificationService = ref.read(notificationServiceProvider);
      await notificationService.requestPermission();

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
            showTime: true,
            initialTime: DateTime.now(),
            timeLabel: 'Päättymisaika',
            visionService: ref.read(odometerVisionServiceProvider),
          ).then((result) {
            if (result != null && context.mounted) {
              tripNotif.stopDriving(result.odometer, endTime: result.time);
              backgroundService.onDrivingStopped();
              // Restart auto-detection
              ref.read(tripDetectionServiceProvider).stop();
              ref.read(tripDetectionServiceProvider).start();
            }
          });
        }
      };

      backgroundService.onStillDriving = () {
        backgroundService.onStillDrivingPressed();
      };

      // Set up trip detection callbacks
      final detectionService = ref.read(tripDetectionServiceProvider);
      final ns = ref.read(notificationServiceProvider);

      detectionService.onStartTripRequested = () {
        // Auto-start trip with most recent route
        final routes = ref.read(routeProvider);
        if (routes.isNotEmpty) {
          _startDriving(routes.first, context);
        }
      };

      ns.onStartTrip = () {
        detectionService.onStartTripRequested?.call();
      };

      ns.onEndTrip = () {
        if (ref.read(tripProvider).activeLeg != null) {
          // Trigger stop driving flow
          backgroundService.onArrived?.call();
        }
      };

      // Start auto-detection if not already driving
      if (!ref.read(tripProvider.notifier).isDriving) {
        detectionService.updateSettings(settings);
        detectionService.start();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final routes = ref.watch(routeProvider);
    final tripState = ref.watch(tripProvider);
    final settings = ref.watch(settingsProvider);
    final tripNotifier = ref.read(tripProvider.notifier);
    final allRecent =
        ref.read(routeProvider.notifier).getRecentRoutes(limit: 1000);
    final recentRoutes = allRecent
        .take(_recentRoutesToShow(
          context,
          total: allRecent.length,
          hasActiveTrip: tripState.activeLeg != null,
          todayLegCount: tripState.todayLegs.length,
        ))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajopäiväkirja'),
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
            ActiveTripCard(
              leg: tripState.activeLeg!,
              onStopDriving: (odometer, {endTime, endLocation, purpose}) async {
                await tripNotifier.stopDriving(odometer,
                    endTime: endTime,
                    endLocation: endLocation,
                    purpose: purpose);
                await ref.read(backgroundServiceProvider).onDrivingStopped();
                // Restart auto-detection
                ref.read(tripDetectionServiceProvider).stop();
                ref.read(tripDetectionServiceProvider).start();
              },
              onCancel: () async {
                await tripNotifier.cancelDriving();
                await ref.read(backgroundServiceProvider).onDrivingStopped();
                ref.read(tripDetectionServiceProvider).stop();
                ref.read(tripDetectionServiceProvider).start();
              },
              visionService: ref.read(odometerVisionServiceProvider),
            ),
            const SizedBox(height: 24),
          ],
          if (tripState.activeLeg == null) ...[
            FilledButton.icon(
              onPressed: () => _startAdHocDriving(context),
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Aloita ajo'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 20),
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



  /// How many recent-route cards fit on screen alongside the other home
  /// content (start button, today summary, history). Estimate-based since
  /// the body is an unbounded scrolling list.
  int _recentRoutesToShow(
    BuildContext context, {
    required int total,
    required bool hasActiveTrip,
    required int todayLegCount,
  }) {
    if (total <= 0) return 0;
    final media = MediaQuery.of(context);
    final screen = media.size.height -
        media.padding.top -
        media.padding.bottom -
        kToolbarHeight;

    double reserved = 32; // list padding
    reserved += 28 + 8; // "Viimeisimmät reitit" header
    reserved += 44 + 8; // "Kaikki reitit" button
    reserved += 52 + 16; // "Historia" button
    if (hasActiveTrip) {
      reserved += 250 + 24; // active trip card
    } else {
      reserved += 48 + 20; // "Aloita ajo" button
    }
    if (todayLegCount > 0) {
      reserved += 120 + todayLegCount * 24 + 24; // today summary card
    }

    const cardHeight = 84.0;
    final available = screen - reserved;
    final fits = (available / cardHeight).floor();
    return fits.clamp(1, total);
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
    final disabled = tripNotifier.isDriving;

    return InkWell(
      onTap: disabled ? null : () => _startDriving(route, context),
      borderRadius: BorderRadius.circular(12),
      child: Card(
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
                onPressed: disabled ? null : () => _startDriving(route, context),
                child: const Text('Aloita'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startAdHocDriving(BuildContext context) async {
    final tripNotifier = ref.read(tripProvider.notifier);
    final settings = ref.read(settingsProvider);

    final lastLeg = await DatabaseService.getLastLeg();
    final initialOdometer = lastLeg?.endOdometer;

    List<String> suggestions = const [];
    try {
      suggestions = await DatabaseService.getUniqueLocations();
    } catch (_) {}

    if (!context.mounted) return;
    final result = await showOdometerDialog(
      context: context,
      title: 'Aloita ajo',
      label: 'Matkamittari (km)',
      actionLabel: 'Aloita ajo',
      locationLabel: 'Lähtöpaikka',
      locationSuggestions: suggestions,
      initialValue: initialOdometer,
      showTime: true,
      initialTime: DateTime.now(),
      timeLabel: 'Alkamisaika',
      visionService: ref.read(odometerVisionServiceProvider),
    );

    if (result == null) return;

    final backgroundService = ref.read(backgroundServiceProvider);
    ref.read(tripDetectionServiceProvider).stop();
    backgroundService.updateSettings(settings);
    final leg = await tripNotifier.startAdHocDriving(
      startOdometer: result.odometer,
      startLocation: result.location ?? '',
      driver: settings.driverName,
      startTime: result.time,
    );
    await backgroundService.onDrivingStarted(leg);
  }

  Future<void> _startDriving(model.Route route, BuildContext context) async {
    final tripNotifier = ref.read(tripProvider.notifier);
    final routeNotifier = ref.read(routeProvider.notifier);
    final settings = ref.read(settingsProvider);

    final lastLeg = await DatabaseService.getLastLeg();
    final initialOdometer = lastLeg?.endOdometer;

    // Try to get GPS-based location suggestion
    String? locationHint;
    try {
      final locationService = ref.read(locationServiceProvider);
      if (await locationService.hasPermission()) {
        final pos = await locationService.getCurrentPosition();
        if (pos != null && mounted) {
          locationHint = await locationService.getLocationName(pos);
        }
      }
    } catch (_) {
      // GPS unavailable, proceed without location hint
    }

    final subtitle = StringBuffer();
    subtitle.writeln('Reitti: ${route.name}');
    subtitle.writeln('${route.startLocation} → ${route.endLocation}');
    subtitle.writeln('Matka: ${route.distanceKm.toStringAsFixed(1)} km');
    if (locationHint != null) {
      subtitle.writeln('📍 Sijaintisi: $locationHint');
    }

    if (!context.mounted) return;
    final result = await showOdometerDialog(
      context: context,
      title: 'Aloita ajo',
      subtitle: subtitle.toString().trim(),
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

    if (result != null) {
      final backgroundService = ref.read(backgroundServiceProvider);
      // Stop auto-detection while we know the user is driving
      ref.read(tripDetectionServiceProvider).stop();
      backgroundService.updateSettings(settings);
      final leg = await tripNotifier.startDriving(
        route: route,
        startOdometer: result.odometer,
        purpose: result.purpose ?? '',
        driver: settings.driverName,
        startTime: result.time,
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

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TripHistoryScreen()),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Card(
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
                        Expanded(
                          child: Text(
                            '${leg.startLocation} → ${leg.endLocation ?? '...'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
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
