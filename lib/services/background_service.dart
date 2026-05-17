import 'dart:async';
import '../models/trip_leg.dart';
import '../models/app_settings.dart';
import 'location_service.dart';
import 'notification_service.dart';

class BackgroundService {
  final NotificationService _notificationService;
  final LocationService _locationService;
  Timer? _reminderTimer;

  TripLeg? _activeLeg;
  AppSettings _settings = const AppSettings();

  void Function()? onArrived;
  void Function()? onStillDriving;

  BackgroundService({
    required NotificationService notificationService,
    required LocationService locationService,
  })  : _notificationService = notificationService,
        _locationService = locationService;

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

    _scheduleTimeBasedReminder(leg);
  }

  void _scheduleTimeBasedReminder(TripLeg leg) {
    _reminderTimer?.cancel();

    final now = DateTime.now();
    final triggerTime = now.add(const Duration(minutes: 30));

    _notificationService.scheduleTimeBasedReminder(
      leg.endLocation ?? leg.routeDescription ?? 'määränpää',
      triggerTime,
    );

    _reminderTimer = Timer(const Duration(minutes: 30), () {
      if (_activeLeg != null) {
        _notificationService.showArrivalReminder(
          leg.endLocation ?? leg.routeDescription ?? 'määränpää',
        );
      }
    });
  }

  Future<void> onDrivingStopped() async {
    _activeLeg = null;
    _reminderTimer?.cancel();
    _reminderTimer = null;

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
    _locationService.dispose();
  }
}
