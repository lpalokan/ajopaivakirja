import 'dart:async';
import '../models/trip_leg.dart';
import '../models/app_settings.dart';
import 'activity_recognition_service.dart';
import 'location_service.dart';
import 'notification_service.dart';

class BackgroundService {
  /// How often the in-process poll re-checks whether the driver is still in
  /// a vehicle. Every increment the current motion is consulted: while the
  /// activity is `in_vehicle` the prompt is suppressed entirely, and only
  /// once the framework reports the driver has left the vehicle is the
  /// "Oletko perillä?" reminder shown. Short (5 min) because the
  /// activity check — not a blind timer — gates whether anything is shown,
  /// so it no longer fires mid-drive the way the old 30/45-minute blind
  /// backstop did.
  static const Duration defaultReminderDuration = Duration(minutes: 5);

  /// Far-out platform-scheduled fallback that only matters if the app
  /// process is killed before any in-process poll can run (an in-process
  /// [Timer] dies with the process). While the process is alive each poll
  /// pushes this fallback forward, so it never actually fires; it is the
  /// blind safety net for "process died mid-trip", deliberately kept long
  /// so that net is not aggressive.
  static const Duration defaultPlatformBackstopDuration = Duration(minutes: 45);

  final NotificationService _notificationService;
  final LocationService _locationService;
  final ActivityRecognitionService _activityService;
  final Duration _reminderDuration;
  final Duration _platformBackstopDuration;

  Timer? _reminderTimer;
  StreamSubscription<DrivingActivity>? _activitySub;
  DrivingActivity _lastActivity = DrivingActivity.unknown;

  /// True once the "Oletko perillä?" reminder has been shown for the
  /// current out-of-vehicle episode, so the 5-minute poll asks once per stop
  /// instead of re-posting the same prompt on every increment. Reset when
  /// the activity returns to `in_vehicle` (a fresh stop can prompt again) or
  /// when the driver taps "Ajan yhä" (snooze, then re-ask if still stopped).
  bool _reminderShown = false;

  TripLeg? _activeLeg;
  AppSettings _settings = const AppSettings();

  void Function()? onArrived;
  void Function()? onStillDriving;

  BackgroundService({
    required NotificationService notificationService,
    required LocationService locationService,
    required ActivityRecognitionService activityService,
    Duration reminderDuration = defaultReminderDuration,
    Duration platformBackstopDuration = defaultPlatformBackstopDuration,
  })  : _notificationService = notificationService,
        _locationService = locationService,
        _activityService = activityService,
        _reminderDuration = reminderDuration,
        _platformBackstopDuration = platformBackstopDuration;

  Future<void> initialize() async {
    await _notificationService.initialize();
    _notificationService.onArrived = () => onArrived?.call();
    _notificationService.onStillDriving = () => onStillDriving?.call();
  }

  void updateSettings(AppSettings settings) {
    _settings = settings;
  }

  Future<void> onDrivingStarted(TripLeg leg) async {
    _activeLeg = leg;
    _reminderShown = false;

    await _notificationService.showDrivingNotification(leg);

    final hasLocation = await _locationService.hasPermissionGranted();
    if (hasLocation) {
      await _locationService.startMonitoringDestination(
        leg.endLocation ?? leg.routeDescription ?? 'määränpää',
        _settings,
        _onProximityNearHome,
      );
    }

    // Best-effort: if activity recognition isn't available or permission is
    // denied, _lastActivity stays at .unknown, which the poll treats like
    // "not in a vehicle" — so the reminder still surfaces (just without the
    // in_vehicle suppression that would otherwise keep it silent mid-drive).
    _activitySub?.cancel();
    _activitySub = _activityService.activityStream.listen((a) {
      _lastActivity = a;
    });
    try {
      await _activityService.start();
    } catch (_) {
      // Swallow — activity is best-effort.
    }

    _scheduleTimeBasedReminder(leg);
  }

  void _scheduleTimeBasedReminder(TripLeg leg) {
    _reminderTimer?.cancel();

    final destination =
        leg.endLocation ?? leg.routeDescription ?? 'määränpää';

    // Platform-level fallback (re)scheduled far enough out that, while the
    // process is alive, the 5-minute in-process poll below always fires
    // first and pushes this forward again — so it never fires its own copy
    // and there is no duplicate notification. It only fires if the process
    // is killed and no poll runs for the whole backstop window.
    final platformTrigger = DateTime.now().add(_platformBackstopDuration);
    _notificationService.scheduleTimeBasedReminder(destination, platformTrigger);

    _reminderTimer = Timer(_reminderDuration, () => _onReminderTick(leg));
  }

  /// Callback the [LocationService]'s proximity Timer invokes when the
  /// user is inside the home zone. Gated on `_activeLeg != null` so a
  /// proximity tick that fires AFTER the trip ended (race between
  /// `stopMonitoring` and the 30-second tick, or a leaked Timer from a
  /// previous session) does not re-post "Oletko perillä?" indefinitely.
  Future<void> _onProximityNearHome(String destination) async {
    if (_activeLeg == null) return;
    await _notificationService.showArrivalReminder(destination);
  }

  Future<void> _onReminderTick(TripLeg leg) async {
    if (_activeLeg == null) return;

    if (_lastActivity == DrivingActivity.inVehicle) {
      // Still in a vehicle — suppress the prompt entirely and keep polling.
      // Reset the "shown" latch so that whenever the driver next leaves the
      // vehicle the reminder is asked again for that fresh stop.
      _reminderShown = false;
      _scheduleTimeBasedReminder(leg);
      return;
    }

    // Confirmed not-in-vehicle (on_foot/still/etc.) or activity recognition
    // unavailable (_lastActivity still .unknown). Ask once per stop episode
    // — the latch keeps the 5-minute poll from re-posting the same prompt on
    // every increment while the driver stays stopped. The poll keeps running
    // so a later return-to-vehicle (which resets the latch) and a subsequent
    // stop can prompt again.
    if (!_reminderShown) {
      _reminderShown = true;
      await _notificationService.showArrivalReminder(
        leg.endLocation ?? leg.routeDescription ?? 'määränpää',
      );
    }
    _scheduleTimeBasedReminder(leg);
  }

  Future<void> onDrivingStopped() async {
    _activeLeg = null;
    _reminderShown = false;
    _reminderTimer?.cancel();
    _reminderTimer = null;
    await _activitySub?.cancel();
    _activitySub = null;
    _lastActivity = DrivingActivity.unknown;
    try {
      await _activityService.stop();
    } catch (_) {}

    await _notificationService.cancelDrivingNotification();
    await _notificationService.cancelReminders();
    await _locationService.stopMonitoring();
  }

  /// Driver tapped "Ajan yhä". Dismiss whatever reminder is currently on
  /// screen (the in-process "Oletko perillä?" and the platform backstop)
  /// so the prompt reliably goes away — the previous bug was that pressing
  /// it left the notification up — then snooze another 5-minute increment.
  /// The latch is cleared so that if the driver is still out of the vehicle
  /// at the next poll the prompt is asked again.
  Future<void> onStillDrivingPressed() async {
    if (_activeLeg == null) return;
    await _notificationService.cancelReminders();
    _reminderShown = false;
    _scheduleTimeBasedReminder(_activeLeg!);
  }

  void dispose() {
    _reminderTimer?.cancel();
    _activitySub?.cancel();
    _activityService.dispose();
    _locationService.dispose();
  }
}
