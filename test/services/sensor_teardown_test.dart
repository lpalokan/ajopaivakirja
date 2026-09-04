import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/models/trip_leg.dart';
import 'package:kilometrikorvaus/services/activity_recognition_service.dart';
import 'package:kilometrikorvaus/services/background_service.dart';
import 'package:kilometrikorvaus/services/location_service.dart';
import 'package:kilometrikorvaus/services/notification_service.dart';
import 'package:kilometrikorvaus/services/reminder_store.dart';

/// Headless companion to the Gherkin scenarios in
/// `integration_test/features/battery.feature`. The scenarios are the source
/// of truth for the behaviour; these run the same teardown on the host VM,
/// where a failure can be pinned to one step.
class _FakeNotificationService extends NotificationService {
  bool failCancelDriving = false;
  bool drivingCancelled = false;
  bool remindersCancelled = false;

  @override
  Future<void> initialize() async {}
  @override
  Future<void> showDrivingNotification(TripLeg leg) async {}
  @override
  Future<void> scheduleTimeBasedReminder(String d, DateTime t) async {}
  @override
  Future<void> cancelDrivingNotification() async {
    if (failCancelDriving) throw Exception('notification channel unavailable');
    drivingCancelled = true;
  }

  @override
  Future<void> cancelReminders() async {
    remindersCancelled = true;
  }
}

class _FakeLocationService extends LocationService {
  bool tripStreamOpen = false;
  bool failNextStop = false;
  int stopCount = 0;

  @override
  bool get isMonitoring => tripStreamOpen;

  @override
  Future<bool> hasPermissionGranted() async => true;

  @override
  Future<void> startMonitoringDestination(
    String destinationName,
    Future<void> Function(String destination) onArrived,
  ) async {
    tripStreamOpen = true;
  }

  @override
  Future<void> stopMonitoring() async {
    stopCount++;
    if (failNextStop) {
      failNextStop = false;
      throw Exception('location channel unavailable');
    }
    tripStreamOpen = false;
  }
}

class _FakeActivityRecognitionService extends ActivityRecognitionService {
  final _controller = StreamController<DrivingActivity>.broadcast();
  bool stopped = false;

  @override
  Stream<DrivingActivity> get activityStream => _controller.stream;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  void dispose() {
    _controller.close();
  }
}

/// The real store talks to SharedPreferences, which has no platform side on
/// the host VM. This one answers in memory.
class _FakeReminderStore extends ReminderStore {
  bool cleared = false;

  @override
  Future<void> clear() async {
    cleared = true;
  }

  @override
  Future<void> setDestination(String destination) async {}
  @override
  Future<DateTime?> snoozedUntil() async => null;
}

TripLeg _leg() => TripLeg(
  id: 1,
  date: '2026-09-04',
  legOrder: 1,
  startTime: DateTime.now(),
  startOdometer: 1000,
  startLocation: 'Koti',
  endLocation: 'Asiakkaan toimistolle',
  driver: 'Kuljettaja',
);

({
  BackgroundService bg,
  _FakeNotificationService notification,
  _FakeLocationService location,
  _FakeActivityRecognitionService activity,
  _FakeReminderStore store,
})
_build({Duration watchdog = const Duration(seconds: 60)}) {
  final notification = _FakeNotificationService();
  final location = _FakeLocationService();
  final activity = _FakeActivityRecognitionService();
  final store = _FakeReminderStore();
  final bg = BackgroundService(
    notificationService: notification,
    locationService: location,
    activityService: activity,
    reminderStore: store,
    sensorWatchdogInterval: watchdog,
  );
  return (
    bg: bg,
    notification: notification,
    location: location,
    activity: activity,
    store: store,
  );
}

void main() {
  group('trip teardown', () {
    test('takes the GPS down even when a notification cancel throws', () async {
      final t = _build();
      t.notification.failCancelDriving = true;

      await t.bg.onDrivingStarted(_leg());
      expect(t.location.tripStreamOpen, isTrue);

      await t.bg.onDrivingStopped();

      expect(
        t.location.tripStreamOpen,
        isFalse,
        reason:
            'A failing notification cancel must not leave the trip position '
            'stream — and the location foreground service behind it — open.',
      );
      t.bg.dispose();
    });

    test('carries on past a failing GPS teardown', () async {
      final t = _build();
      t.location.failNextStop = true;

      await t.bg.onDrivingStarted(_leg());
      await t.bg.onDrivingStopped();

      expect(t.activity.stopped, isTrue);
      expect(t.store.cleared, isTrue);
      expect(t.notification.drivingCancelled, isTrue);
      expect(t.notification.remindersCancelled, isTrue);
      t.bg.dispose();
    });
  });

  group('sensor watchdog', () {
    test('forces down a location hold that outlived its trip', () async {
      final t = _build(watchdog: const Duration(milliseconds: 50));
      t.location.failNextStop = true;

      await t.bg.onDrivingStarted(_leg());
      await t.bg.onDrivingStopped();
      expect(
        t.location.tripStreamOpen,
        isTrue,
        reason: 'The teardown failed, so the hold is still open here.',
      );

      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(
        t.location.tripStreamOpen,
        isFalse,
        reason: 'The watchdog is the only thing left to ask a second time.',
      );
      t.bg.dispose();
    });

    test('leaves a running trip alone', () async {
      final t = _build(watchdog: const Duration(milliseconds: 50));

      await t.bg.onDrivingStarted(_leg());
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(t.location.tripStreamOpen, isTrue);
      expect(t.location.stopCount, 0);
      t.bg.dispose();
    });

    test('stops ticking once the trip has been torn down', () async {
      final t = _build(watchdog: const Duration(milliseconds: 50));

      await t.bg.onDrivingStarted(_leg());
      await t.bg.onDrivingStopped();
      final stopsAfterTeardown = t.location.stopCount;

      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(
        t.location.stopCount,
        stopsAfterTeardown,
        reason: 'A successful teardown must disarm the watchdog.',
      );
      t.bg.dispose();
    });
  });
}
