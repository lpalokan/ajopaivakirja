import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import '../models/route.dart' as model;
import '../models/trip_leg.dart';
import '../models/app_settings.dart';
import '../providers/route_provider.dart';
import '../providers/trip_provider.dart';
import '../providers/settings_provider.dart';
import '../services/database_service.dart';
import '../services/log_service.dart';
import '../widgets/start_card.dart';
import '../widgets/active_trip_card.dart';
import '../widgets/route_chip_row.dart';
import '../widgets/location_chip.dart';
import '../widgets/day_timeline.dart';
import 'settings_screen.dart';
import 'route_management_screen.dart';
import 'trip_history_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _startCardKey = GlobalKey<StartCardState>();
  int? _selectedRouteId;
  String? _selectedStartLocation;
  String? _selectedPurpose;
  final double _liveDistanceKm = 0;

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

      await backgroundService.initialize();

      final notificationService = ref.read(notificationServiceProvider);
      await notificationService.requestPermission();

      backgroundService.onArrived = () {
        final activeLeg = ref.read(tripProvider).activeLeg;
        if (activeLeg != null) {
          final expectedOdometer =
              activeLeg.startOdometer + activeLeg.kmDriven.toInt();
          _showArrivalDialog(context, activeLeg, expectedOdometer);
        }
      };

      backgroundService.onStillDriving = () {
        backgroundService.onStillDrivingPressed();
      };

      // Set up trip detection callbacks
      final detectionService = ref.read(tripDetectionServiceProvider);
      final ns = ref.read(notificationServiceProvider);

      detectionService.onStartTripRequested = () {
        final routes = ref.read(routeProvider);
        if (routes.isNotEmpty) {
          _startWithRoute(routes.first);
        }
      };

      ns.onStartTrip = () {
        detectionService.onStartTripRequested?.call();
      };

      ns.onEndTrip = () {
        if (ref.read(tripProvider).activeLeg != null) {
          backgroundService.onArrived?.call();
        }
      };

      ns.flushPendingLaunchAction();

      if (!ref.read(tripProvider.notifier).isDriving) {
        detectionService.updateSettings(settings);
        detectionService.start();
      }
    });
  }

  void _showArrivalDialog(
      BuildContext context, TripLeg activeLeg, int expectedOdometer) {
    // Delegate to the standard arrival dialog in odometer_dialog.dart
    // This is triggered from background service callback.
    final tripNotif = ref.read(tripProvider.notifier);
    final backgroundService = ref.read(backgroundServiceProvider);

    // Use a post-frame callback because we might not have a valid context
    // from the background callback.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // The arrival dialog was previously in home_screen
      // We keep the same flow but simplified.
      tripNotif.stopDriving(expectedOdometer, endTime: DateTime.now());
      backgroundService.onDrivingStopped();
      ref.read(tripDetectionServiceProvider).stop();
      ref.read(tripDetectionServiceProvider).start();
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
    final recentRoutes =
        allRecent.take(4).toList();

    final lastOdometerFuture = tripState.activeLeg == null
        ? DatabaseService.getLastLeg()
        : null;

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
      body: tripState.activeLeg != null
          ? _buildActiveBody(tripState, tripNotifier)
          : _buildIdleBody(tripState, routes, settings, tripNotifier,
              recentRoutes, lastOdometerFuture),
    );
  }

  Widget _buildActiveBody(
      TripState tripState, TripNotifier tripNotifier) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Hero active trip card at the top
        ActiveTripCard(
          leg: tripState.activeLeg!,
          liveDistanceKm: _liveDistanceKm,
          onStopDriving:
              (odometer, {endTime, endLocation, purpose}) async {
            await tripNotifier.stopDriving(odometer,
                endTime: endTime,
                endLocation: endLocation,
                purpose: purpose);
            await ref
                .read(backgroundServiceProvider)
                .onDrivingStopped();
            ref.read(tripDetectionServiceProvider).stop();
            ref.read(tripDetectionServiceProvider).start();
          },
          onCancel: () async {
            await tripNotifier.cancelDriving();
            await ref
                .read(backgroundServiceProvider)
                .onDrivingStopped();
            ref.read(tripDetectionServiceProvider).stop();
            ref.read(tripDetectionServiceProvider).start();
          },
          visionService: ref.read(odometerVisionServiceProvider),
        ),
        const SizedBox(height: 16),
        // Day timeline in the middle
        if (tripState.todayLegs.isNotEmpty)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                DayTimeline(
                  legs: tripState.todayLegs,
                  onTapLeg: (leg) {
                    // Navigate to history for editing
                    Navigator.of(context)
                        .push(
                      MaterialPageRoute(
                          builder: (_) =>
                              const TripHistoryScreen()),
                    );
                  },
                ),
              ],
            ),
          )
        else
          const Spacer(),
        // Bottom-anchored "Olen perillä" CTA (thumb zone)
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: () {
                  final activeLeg = tripState.activeLeg;
                  if (activeLeg != null) {
                    final expectedOdometer =
                        activeLeg.startOdometer +
                            activeLeg.kmDriven.toInt();
                    // Trigger the same stop flow
                    tripNotifier.stopDriving(
                      expectedOdometer,
                      endTime: DateTime.now(),
                    );
                    ref
                        .read(backgroundServiceProvider)
                        .onDrivingStopped();
                    ref.read(tripDetectionServiceProvider).stop();
                    ref.read(tripDetectionServiceProvider).start();
                  }
                },
                icon: const Icon(Icons.flag),
                label: const Text('Olen perillä'),
                style: FilledButton.styleFrom(
                  backgroundColor:
                      colorScheme.primaryContainer,
                  foregroundColor:
                      colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIdleBody(
    TripState tripState,
    List<model.Route> routes,
    AppSettings settings,
    TripNotifier tripNotifier,
    List<model.Route> recentRoutes,
    Future<TripLeg?>? lastOdometerFuture,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Status zone (top ~38% — read only)
        if (tripState.todayLegs.isNotEmpty)
          DayTimeline(
            legs: tripState.todayLegs,
            onTapLeg: (leg) {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const TripHistoryScreen()),
              );
            },
          ),
        if (tripState.todayLegs.isEmpty)
          Expanded(
            flex: 3,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_road,
                      size: 56,
                      color: colorScheme.outline),
                  const SizedBox(height: 8),
                  Text('Ei matkoja tänään',
                      style:
                          Theme.of(context).textTheme.bodyLarge),
                  Text(
                    'Aloita ajo alla olevasta lomakkeesta.',
                    style: TextStyle(
                        color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        // Route chips (middle ~28%)
        if (recentRoutes.isNotEmpty) ...[
          RouteChipRow(
            routes: recentRoutes,
            selectedRouteId: _selectedRouteId,
            onRouteSelected: (route) {
              if (route.id == _selectedRouteId) {
                // Deselect
                setState(() {
                  _selectedRouteId = null;
                  _selectedStartLocation = null;
                  _selectedPurpose = null;
                });
              } else {
                setState(() {
                  _selectedRouteId = route.id;
                  _selectedStartLocation = route.startLocation;
                  _selectedPurpose = route.lastPurpose;
                });
                // Pre-fill odometer from StartCard
                if (_startCardKey.currentState != null) {
                  // Odometer is pre-filled from lastLeg; no change needed
                }
              }
            },
            onShowAll: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) =>
                        const RouteManagementScreen()),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
        // Bottom ~34% — StartCard (primary action zone)
        FutureBuilder<TripLeg?>(
          future: lastOdometerFuture,
          builder: (context, snapshot) {
            final lastOdometer =
                snapshot.data?.endOdometer;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: StartCard(
                key: _startCardKey,
                initialOdometer: lastOdometer,
                selectedRouteLabel: _selectedStartLocation != null
                    ? 'Reitti: $_selectedStartLocation'
                    : null,
                onStart: () =>
                    _onStartTap(tripNotifier, settings),
                visionService:
                    ref.read(odometerVisionServiceProvider),
                locationChip: LocationChip(
                  locationService:
                      ref.read(locationServiceProvider),
                  fallbackLabel:
                      _selectedStartLocation ?? settings.homeLocation,
                  onChanged: (loc) {
                    setState(
                        () => _selectedStartLocation = loc);
                  },
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _onStartTap(
      TripNotifier tripNotifier, AppSettings settings) async {
    final odometer = _startCardKey.currentState?.odometerValue;
    if (odometer == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Syötä mittarilukema')),
        );
      }
      return;
    }

    final startLocation = _selectedStartLocation ?? settings.homeLocation;
    final purpose = _selectedPurpose ?? '';

    // Stop auto-detection while driving
    ref.read(tripDetectionServiceProvider).stop();
    final backgroundService = ref.read(backgroundServiceProvider);
    backgroundService.updateSettings(settings);

    model.Route? selectedRoute;
    if (_selectedRouteId != null) {
      selectedRoute =
          ref.read(routeProvider).firstWhere((r) => r.id == _selectedRouteId);
    }

    TripLeg leg;
    if (selectedRoute != null) {
      leg = await tripNotifier.startDriving(
        route: selectedRoute,
        startOdometer: odometer,
        purpose: purpose,
        driver: settings.driverName,
      );
      if (selectedRoute.id != null && purpose.isNotEmpty) {
        await ref
            .read(routeProvider.notifier)
            .savePurpose(selectedRoute.id!, purpose);
      }
      if (selectedRoute.id != null) {
        await ref.read(routeProvider.notifier).markUsed(selectedRoute.id!);
      }
    } else {
      leg = await tripNotifier.startAdHocDriving(
        startOdometer: odometer,
        startLocation: startLocation,
        purpose: purpose,
        driver: settings.driverName,
      );
    }

    await backgroundService.onDrivingStarted(leg);

    setState(() {
      _selectedRouteId = null;
      _selectedStartLocation = null;
      _selectedPurpose = null;
    });
  }

  Future<void> _startWithRoute(model.Route route) async {
    final tripNotifier = ref.read(tripProvider.notifier);
    final settings = ref.read(settingsProvider);

    final lastLeg = await DatabaseService.getLastLeg();
    final initialOdometer = lastLeg?.endOdometer;
    if (initialOdometer == null) return;

    ref.read(tripDetectionServiceProvider).stop();
    final backgroundService = ref.read(backgroundServiceProvider);
    backgroundService.updateSettings(settings);

    final leg = await tripNotifier.startDriving(
      route: route,
      startOdometer: initialOdometer,
      purpose: route.lastPurpose ?? '',
      driver: settings.driverName,
    );
    await backgroundService.onDrivingStarted(leg);
    if (route.id != null && route.lastPurpose != null &&
        route.lastPurpose!.isNotEmpty) {
      await ref.read(routeProvider.notifier)
          .savePurpose(route.id!, route.lastPurpose!);
    }
    if (route.id != null) {
      await ref.read(routeProvider.notifier).markUsed(route.id!);
    }
  }
}
