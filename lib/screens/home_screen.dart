import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import '../models/route.dart' as model;
import '../models/trip_leg.dart';
import '../models/app_settings.dart';
import '../providers/position_provider.dart';
import '../providers/route_provider.dart';
import '../providers/trip_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/update_check_provider.dart';
import '../services/database_service.dart';
import '../services/log_service.dart';
import '../widgets/start_card.dart';
import '../widgets/active_trip_card.dart';
import '../widgets/route_chip_row.dart';
import '../widgets/location_chip.dart';
import '../widgets/day_timeline.dart';
import '../widgets/top_context_card.dart';
import '../widgets/update_banner.dart';
import '../widgets/main_bottom_nav.dart';
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

      // Resolve where we are, then keep following while the screen is up.
      // A trip has its own position stream, so the idle watch stays off
      // while one is running (see the tripProvider listener in build).
      final position = ref.read(currentPositionProvider.notifier);
      await position.refresh();
      if (ref.read(tripProvider).activeLeg == null) position.startIdleWatch();

      final backgroundService = ref.read(backgroundServiceProvider);
      await backgroundService.initialize();

      final notificationService = ref.read(notificationServiceProvider);
      await notificationService.requestPermission();

      // Let notification-triggered arrivals present the arrival dialog on
      // this live screen (mirrors the in-app "Olen perillä" button). Wire it
      // BEFORE initialize() so a cold-launch action replayed by
      // flushPendingLaunchAction finds the presenter and shows the dialog
      // instead of falling back to the estimated odometer. The mounted guard
      // makes a stale presenter (after the screen is torn down) a no-op.
      tripNotif2.setArrivalPresenter(() async {
        if (!mounted) return;
        await tripNotif2.stopTrip(context);
      });

      // Delegate all callback wiring and detection lifecycle to
      // TripNotifier — the orchestration seam for trip state.
      tripNotif2.initialize();

      // Silent update check on startup. Result lands in
      // updateCheckProvider; the UpdateBanner widget watches the same
      // state and surfaces the banner only when an update is found.
      // Errors stay in the provider state — we don't bubble them into
      // a snackbar so a flaky network doesn't nag the user.
      ref.read(updateCheckProvider.notifier).check();
    });
  }

  @override
  void dispose() {
    _odometerNotifier.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final tripNotifier = ref.read(tripProvider.notifier);
    final position = ref.read(currentPositionProvider.notifier);
    if (state == AppLifecycleState.paused) {
      tripNotifier.onAppBackgrounded();
      // Nobody is looking at the chip — stop paying for fixes.
      position.stopIdleWatch();
    } else if (state == AppLifecycleState.resumed) {
      tripNotifier.onAppForegrounded();
      // The driver has almost certainly moved since the app was last on
      // screen; re-resolve before they read the position off the chip.
      position.refresh();
      if (ref.read(tripProvider).activeLeg == null) position.startIdleWatch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final routes = ref.watch(routeProvider);
    final tripState = ref.watch(tripProvider);
    final settings = ref.watch(settingsProvider);

    // An active trip already runs a position stream; a second idle one would
    // pay for the same fixes twice.
    ref.listen<TripState>(tripProvider, (previous, next) {
      final position = ref.read(currentPositionProvider.notifier);
      if (next.activeLeg != null) {
        position.stopIdleWatch();
      } else {
        position.startIdleWatch();
      }
    });

    // Shortcut row: the routes that start where we are, falling back to the
    // recently driven ones whenever the position can't answer — an empty row
    // would read as lost data.
    final nearbyRoutes = ref.watch(nearbyRoutesProvider);
    final showingNearby = nearbyRoutes.isNotEmpty;
    var shortcutRoutes = showingNearby
        ? nearbyRoutes
        : ref.read(routeProvider.notifier).getRecentRoutes(limit: 2);
    // A route the user has already tapped stays on screen even if the next
    // fix would drop it from the list: a chip must never change identity
    // between finger-down and finger-up.
    if (_selectedRouteId != null &&
        !shortcutRoutes.any((r) => r.id == _selectedRouteId)) {
      final selected = routes
          .where((r) => r.id == _selectedRouteId)
          .firstOrNull;
      if (selected != null) {
        shortcutRoutes = [selected, ...shortcutRoutes].take(2).toList();
      }
    }

    final lastOdometerFuture = tripState.activeLeg == null
        ? DatabaseService.getLastLeg()
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Ajopäiväkirja')),
      body: tripState.activeLeg != null
          ? _buildActiveBody(tripState)
          : _buildIdleBody(
              tripState,
              routes,
              settings,
              shortcutRoutes,
              showingNearby,
              lastOdometerFuture,
            ),
      bottomNavigationBar: const MainBottomNav(selectedIndex: 0),
    );
  }

  Widget _buildActiveBody(TripState tripState) {
    final colorScheme = Theme.of(context).colorScheme;
    final tripNotifier = ref.read(tripProvider.notifier);

    return Column(
      children: [
        // Hero active trip card at the top
        ActiveTripCard(leg: tripState.activeLeg!),
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
                onPressed: () => tripNotifier.stopTrip(context),
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
    List<model.Route> shortcutRoutes,
    bool showingNearby,
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
        // Surfaces the latest result from `updateCheckProvider`; renders
        // nothing while up-to-date or while a check is still in flight.
        const UpdateBanner(),
        // Top zone — context card. Priority: a selected route preview
        // wins over the day timeline, which wins over the ad-hoc card.
        Expanded(flex: 3, child: _buildTopZone(tripState, selectedRoute)),
        // Route chips
        if (shortcutRoutes.isNotEmpty) ...[
          RouteChipRow(
            title: showingNearby ? 'Lähellä' : 'Viimeksi ajetut',
            routes: shortcutRoutes,
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
                onStart: () => _onStartTap(),
                visionService: ref.read(odometerVisionServiceProvider),
                locationChip: LocationChip(
                  key: _locationChipKey,
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

  Future<void> _onStartTap() async {
    final odometer = _startCardKey.currentState?.odometerValue;
    if (odometer == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Syötä mittarilukema')));
      }
      return;
    }

    final settings = ref.read(settingsProvider);
    final startLocation = _pickedLocation ?? settings.homeLocation;
    final purpose = _selectedPurpose ?? '';

    model.Route? selectedRoute;
    if (_selectedRouteId != null) {
      selectedRoute = ref
          .read(routeProvider)
          .firstWhere((r) => r.id == _selectedRouteId);
    }

    await ref
        .read(tripProvider.notifier)
        .startTrip(
          startOdometer: odometer,
          startLocation: startLocation,
          route: selectedRoute,
          purpose: purpose,
          driver: settings.driverName,
        );

    if (!mounted) return;
    setState(() {
      _selectedRouteId = null;
      _pickedLocation = null;
      _selectedPurpose = null;
    });
  }
}
