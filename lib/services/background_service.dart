import 'dart:async';
import '../models/trip_leg.dart';
import '../models/app_settings.dart';
import 'activity_recognition_service.dart';
import 'location_service.dart';
import 'notification_service.dart';

class BackgroundService {
  /// Backstop interval after which we re-check whether the driver has
  /// actually arrived. Was 30 minutes; bumped to 45 minutes after users
  /// reported the 30-minute prompt firing mid-drive too often.
  static const Duration defaultReminderDuration = Duration(minutes: 45);

  final NotificationService _notificationService;
  final LocationService _locationService;
  final ActivityRecognitionService _activityService;
  final Duration _reminderDuration;

  Timer? _reminderTimer;
  StreamSubscription<DrivingActivity>? _activitySub;
  DrivingActivity _lastActivity = DrivingActivity.unknown;

  TripLeg? _activeLeg;
  AppSettings _settings = const AppSettings();

  void Function()? onArrived;
  void Function()? onStillDriving;

  BackgroundService({
    required NotificationService notificationService,
    required LocationService locationService,
    required ActivityRecognitionService activityService,
    Duration reminderDuration = defaultReminderDuration,
  })  : _notificationService = notificationService,
        _locationService = locationService,
        _activityService = activityService,
        _reminderDuration = reminderDuration;

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

    await _notificationService.showDrivingNotification(leg);

    final hasLocation = await _locationService.hasPermissionGranted();
    if (hasLocation) {
      await _locationService.startMonitoringDestination(
        leg.endLocation ?? leg.routeDescription ?? 'määränpää',
        _settings,
        _notificationService,
      );
    }

    // Best-effort: if activity recognition isn't available or permission is
    // denied, _lastActivity stays at .unknown and the reminder fires as a
    // blind backstop (i.e. today's behaviour, just at 45 min instead of 30).
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
    final triggerTime = DateTime.now().add(_reminderDuration);

    // Platform-level fallback so the reminder still fires if the app
    // process is killed before the in-process timer can run. When the
    // app IS alive at the tick, _onReminderTick cancels this before
    // the platform fires to avoid a duplicate.
    _notificationService.scheduleTimeBasedReminder(destination, triggerTime);

    _reminderTimer = Timer(_reminderDuration, () => _onReminderTick(leg));
  }

  Future<void> _onReminderTick(TripLeg leg) async {
    if (_activeLeg == null) return;

    if (_lastActivity == DrivingActivity.inVehicle) {
      // Still driving — defer. Cancel the pre-scheduled platform notif so
      // it doesn't fire its own copy at the original tick time, then
      // reschedule for another 45 minutes.
      await _notificationService.cancelScheduledReminder();
      _scheduleTimeBasedReminder(leg);
      return;
    }

    // Either confirmed not-in-vehicle (on_foot/still/etc.) or activity
    // recognition unavailable (_lastActivity still .unknown). Show the
    // reminder; the user can then confirm arrival or "Ajan yhä" to
    // restart the backstop.
    await _notificationService.showArrivalReminder(
      leg.endLocation ?? leg.routeDescription ?? 'määränpää',
    );
  }

  Future<void> onDrivingStopped() async {
    _activeLeg = null;
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

  Future<void> onStillDrivingPressed() async {
    if (_activeLeg != null) {
      _scheduleTimeBasedReminder(_activeLeg!);
    }
  }

  void dispose() {
    _reminderTimer?.cancel();
    _activitySub?.cancel();
    _activityService.dispose();
    _locationService.dispose();
  }
}
