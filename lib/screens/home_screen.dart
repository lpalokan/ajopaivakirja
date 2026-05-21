import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import '../services/location_service.dart';
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
import '../widgets/top_context_card.dart';
import '../widgets/odometer_dialog.dart';
import 'settings_screen.dart';
import 'route_management_screen.dart';
import 'trip_history_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  final _startCardKey = GlobalKey<StartCardState>();
  // Stable identity for the location chip: StartCard's Column inserts a
  // leading route-label row once a location is picked, which shifts the
  // chip's child index. Without a GlobalKey, keyless reconciliation would
  // dispose the live chip State mid-callback (the one running the picker
  // dialog), so its `mounted` check fails and the pick is dropped.
  final _locationChipKey = GlobalKey();
  int? _selectedRouteId;
  // Last location the LocationChip emitted. Kept separate from any
  // selected route's start address so the chip's callback can't silently
  // overwrite what the route preview / StartCard banner display.
  String? _pickedLocation;
  String? _selectedPurpose;
  // Live mirror of the StartCard's odometer field, read by the route
  // preview card to compute the expected end odometer.
  final ValueNotifier<int?> _odometerNotifier = ValueNotifier<int?>(null);
  double _liveDistanceKm = 0;
  StreamSubscription<dynamic>? _positionSub;
  dynamic _lastPosition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
          await routeNotifier.add(
            model.Route(
              name: 'Töihin',
              startLocation: 'Koti',
              endLocation: 'Työ',
              distanceKm: 54,
              createdAt: now,
              updatedAt: now,
            ),
          );
          await routeNotifier.add(
            model.Route(
              name: 'Kotiin',
              startLocation: 'Työ',
              endLocation: 'Koti',
              distanceKm: 54,
              createdAt: now,
              updatedAt: now,
            ),
          );
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

      // Subscribe to live GPS position updates for active-trip distance
      _positionSub = ref.read(locationServiceProvider).positionStream.listen((
        pos,
      ) {
        if (!mounted) return;
        final last = _lastPosition;
        _lastPosition = pos;
        if (last != null && ref.read(tripProvider).activeLeg != null) {
          final dist = LocationService.haversineDistance(
            last.latitude,
            last.longitude,
            pos.latitude,
            pos.longitude,
          );
          // Convert meters to km and add to running total
          _liveDistanceKm += dist / 1000.0;
        }
      });
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _odometerNotifier.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final tripNotifier = ref.read(tripProvider.notifier);
    if (state == AppLifecycleState.paused) {
      tripNotifier.onAppBackgrounded();
    } else if (state == AppLifecycleState.resumed) {
      tripNotifier.onAppForegrounded();
    }
  }

  void _showArrivalDialog(
    BuildContext context,
    TripLeg activeLeg,
    int expectedOdometer,
  ) {
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
    final allRecent = ref
        .read(routeProvider.notifier)
        .getRecentRoutes(limit: 1000);
    final recentRoutes = allRecent.take(4).toList();

    final lastOdometerFuture = tripState.activeLeg == null
        ? DatabaseService.getLastLeg()
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajopäiväkirja'),
        actions: [
          IconButton(
            icon: const Icon(Symbols.history),
            tooltip: 'Historia',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TripHistoryScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Symbols.settings),
            tooltip: 'Asetukset',
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
        ],
      ),
      body: tripState.activeLeg != null
          ? _buildActiveBody(tripState, tripNotifier)
          : _buildIdleBody(
              tripState,
              routes,
              settings,
              tripNotifier,
              recentRoutes,
              lastOdometerFuture,
            ),
    );
  }

  Widget _buildActiveBody(TripState tripState, TripNotifier tripNotifier) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Hero active trip card at the top
        ActiveTripCard(
          leg: tripState.activeLeg!,
          liveDistanceKm: _liveDistanceKm,
          onStopDriving: (odometer, {endTime, endLocation, purpose}) async {
            await tripNotifier.stopDriving(
              odometer,
              endTime: endTime,
              endLocation: endLocation,
              purpose: purpose,
            );
            _liveDistanceKm = 0;
            _lastPosition = null;
            await ref.read(backgroundServiceProvider).onDrivingStopped();
            ref.read(tripDetectionServiceProvider).stop();
            ref.read(tripDetectionServiceProvider).start();
          },
          onCancel: () async {
            await tripNotifier.cancelDriving();
            _liveDistanceKm = 0;
            _lastPosition = null;
            await ref.read(backgroundServiceProvider).onDrivingStopped();
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
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TripHistoryScreen(),
                      ),
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
                onPressed: _onBottomArrivePressed,
                icon: const Icon(Symbols.flag),
                label: const Text('Olen perillä'),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primaryContainer,
                  foregroundColor: colorScheme.onPrimaryContainer,
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
    // Resolve the selected route from the live routes list rather than
    // caching its fields in state — keeps the StartCard banner and the
    // route preview rendering from one source of truth.
    final selectedRoute = _selectedRouteId == null
        ? null
        : routes.where((r) => r.id == _selectedRouteId).firstOrNull;

    return Column(
      children: [
        // Top zone — context card. Priority: a selected route preview
        // wins over the day timeline, which wins over the ad-hoc card.
        Expanded(flex: 3, child: _buildTopZone(tripState, selectedRoute)),
        // Route chips
        if (recentRoutes.isNotEmpty) ...[
          RouteChipRow(
            routes: recentRoutes,
            selectedRouteId: _selectedRouteId,
            onRouteSelected: (route) {
              if (route.id == _selectedRouteId) {
                setState(() {
                  _selectedRouteId = null;
                  _selectedPurpose = null;
                });
              } else {
                setState(() {
                  _selectedRouteId = route.id;
                  _selectedPurpose = route.lastPurpose;
                });
              }
            },
            onShowAll: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const RouteManagementScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
        // Bottom — StartCard (primary action zone)
        FutureBuilder<TripLeg?>(
          future: lastOdometerFuture,
          builder: (context, snapshot) {
            final lastOdometer = snapshot.data?.endOdometer;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: StartCard(
                key: _startCardKey,
                initialOdometer: lastOdometer,
                odometerNotifier: _odometerNotifier,
                selectedRouteLabel: selectedRoute != null
                    ? 'Reitti: ${selectedRoute.name} → ${selectedRoute.endLocation}'
                    : null,
                onStart: () => _onStartTap(tripNotifier, settings),
                visionService: ref.read(odometerVisionServiceProvider),
                locationChip: LocationChip(
                  key: _locationChipKey,
                  locationService: ref.read(locationServiceProvider),
                  fallbackLabel:
                      selectedRoute?.startLocation ??
                      _pickedLocation ??
                      settings.homeLocation,
                  onChanged: (loc) {
                    setState(() => _pickedLocation = loc);
                  },
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTopZone(TripState tripState, model.Route? selectedRoute) {
    if (selectedRoute != null) {
      return SingleChildScrollView(
        child: RoutePreviewCard(
          route: selectedRoute,
          odometerListenable: _odometerNotifier,
        ),
      );
    }
    if (tripState.todayLegs.isNotEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          children: [
            DayTimeline(
              legs: tripState.todayLegs,
              onTapLeg: (leg) {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TripHistoryScreen()),
                );
              },
            ),
            const SizedBox(height: 8),
            const AdHocCard(),
          ],
        ),
      );
    }
    return const SingleChildScrollView(child: AdHocCard());
  }

  Future<void> _onStartTap(
    TripNotifier tripNotifier,
    AppSettings settings,
  ) async {
    final odometer = _startCardKey.currentState?.odometerValue;
    if (odometer == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Syötä mittarilukema')));
      }
      return;
    }

    final startLocation = _pickedLocation ?? settings.homeLocation;
    final purpose = _selectedPurpose ?? '';

    // Stop auto-detection while driving
    ref.read(tripDetectionServiceProvider).stop();
    final backgroundService = ref.read(backgroundServiceProvider);
    backgroundService.updateSettings(settings);

    model.Route? selectedRoute;
    if (_selectedRouteId != null) {
      selectedRoute = ref
          .read(routeProvider)
          .firstWhere((r) => r.id == _selectedRouteId);
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

    _liveDistanceKm = 0;
    _lastPosition = null;

    setState(() {
      _selectedRouteId = null;
      _pickedLocation = null;
      _selectedPurpose = null;
    });
  }

  /// Shows the arrival dialog for the active leg when the bottom
  /// "Olen perillä" button is tapped. Mirrors the same dialog flow as
  /// ActiveTripCard._stopDriving.
  Future<void> _onBottomArrivePressed() async {
    final tripState = ref.read(tripProvider);
    final activeLeg = tripState.activeLeg;
    if (activeLeg == null) return;

    final tripNotifier = ref.read(tripProvider.notifier);
    final isAdHoc =
        activeLeg.routeId == null && activeLeg.routeDescription == null;
    final expectedOdometer =
        activeLeg.startOdometer + activeLeg.kmDriven.toInt();

    List<String> suggestions = const [];
    if (isAdHoc) {
      try {
        suggestions = await DatabaseService.getUniqueLocations();
      } catch (_) {}
    }

    if (!mounted) return;

    final result = await showOdometerDialog(
      context: context,
      title: 'Olen perillä',
      subtitle: isAdHoc
          ? 'Lähtö: ${activeLeg.startLocation}'
          : 'Kohde: ${activeLeg.endLocation ?? activeLeg.routeDescription}',
      label: 'Matkamittari perillä (km)',
      actionLabel: 'Lopeta ajo',
      initialValue: isAdHoc ? null : expectedOdometer,
      expectedHint: isAdHoc ? null : expectedOdometer,
      showTime: true,
      initialTime: DateTime.now(),
      timeLabel: 'Päättymisaika',
      locationLabel: isAdHoc ? 'Määränpää' : null,
      locationSuggestions: suggestions,
      relatedField: isAdHoc ? 'Tarkoitus' : null,
      initialPurpose: isAdHoc ? activeLeg.purpose : null,
      visionService: ref.read(odometerVisionServiceProvider),
    );

    if (result != null && mounted) {
      await tripNotifier.stopDriving(
        result.odometer,
        endTime: result.time,
        endLocation: result.location,
        purpose: result.purpose,
      );
      _liveDistanceKm = 0;
      _lastPosition = null;
      await ref.read(backgroundServiceProvider).onDrivingStopped();
      ref.read(tripDetectionServiceProvider).stop();
      ref.read(tripDetectionServiceProvider).start();
    }
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
    _liveDistanceKm = 0;
    _lastPosition = null;
    if (route.id != null &&
        route.lastPurpose != null &&
        route.lastPurpose!.isNotEmpty) {
      await ref
          .read(routeProvider.notifier)
          .savePurpose(route.id!, route.lastPurpose!);
    }
    if (route.id != null) {
      await ref.read(routeProvider.notifier).markUsed(route.id!);
    }
  }
}
