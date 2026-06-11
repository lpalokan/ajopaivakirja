import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../models/trip_leg.dart';
import 'reminder_store.dart';

/// How long one "Ajan yhä" tap silences the arrival reminders — both the
/// 5-minute activity-checked poll and the 30-second proximity check read
/// this snooze (via [ReminderStore]) before prompting again.
const Duration stillDrivingSnoozeDuration = Duration(minutes: 15);

/// How far out the "Ajan yhä" tap re-arms the platform backstop. Mirrors
/// [BackgroundService.defaultPlatformBackstopDuration]: dismissing the
/// visible "Vieläkö ajat?" (id 3) also unschedules any pending copy, so the
/// tap must register a fresh one — it is the only re-prompt left when the
/// app process has been killed mid-trip.
const Duration stillDrivingBackstopRearmDuration = Duration(minutes: 45);

/// Cancels a single platform notification by id. Pulled out as a typedef so
/// the isolate-safe [handleStillDrivingBackgroundAction] can be driven by a
/// real [FlutterLocalNotificationsPlugin] in production and by a recording
/// fake in a host-VM unit test (the plugin class itself can't be subclassed —
/// factory + private constructor).
typedef NotificationCanceller = Future<void> Function(int id);

/// Registers the far-out "Vieläkö ajat?" backstop. A typedef seam for the
/// same reason as [NotificationCanceller].
typedef BackstopScheduler = Future<void> Function(
  String destination,
  DateTime triggerTime,
);

/// Everything the "Ajan yhä" (still-driving) tap must do, written as a pure
/// top-level function so it can run in the background isolate (where the
/// live [BackgroundService] is unreachable) AND be unit-tested directly.
///
/// On Android this is the ONLY code that ever handles the tap: a
/// `showsUserInterface: false` action is always delivered to the background
/// isolate, even while the app is in the foreground. So it must do the whole
/// job by itself:
///
///  1. Dismiss whichever reminder is on screen — the in-process "Oletko
///     perillä?" (id 2) or the fired platform backstop "Vieläkö ajat?"
///     (id 3). Cancelling only id 2 was the bug that left a fired backstop
///     on screen no matter how many times "Ajan yhä" was pressed.
///  2. Persist a snooze deadline through [ReminderStore], because the main
///     isolate's poll and proximity timers know nothing about the tap. They
///     re-read the snooze before every prompt, which is what makes the
///     reminder actually stay away.
///  3. Re-arm the platform backstop: cancelling id 3 also dropped any
///     pending schedule, and if the process is dead that schedule was the
///     only thing left to re-prompt a driver still on the road.
@visibleForTesting
Future<void> handleStillDrivingBackgroundAction(
  NotificationResponse response, {
  required NotificationCanceller cancel,
  required ReminderStore store,
  required BackstopScheduler scheduleBackstop,
  Duration snoozeDuration = stillDrivingSnoozeDuration,
}) async {
  if (response.actionId != NotificationService.stillDrivingActionId) return;
  await cancel(NotificationService.arrivalReminderId);
  await cancel(NotificationService.scheduledReminderId);
  final now = DateTime.now();
  await store.setSnoozedUntil(now.add(snoozeDuration));
  final destination = await store.destination() ?? 'määränpää';
  await scheduleBackstop(
    destination,
    now.add(stillDrivingBackstopRearmDuration),
  );
}

/// Handles notification action taps delivered to the background isolate.
///
/// flutter_local_notifications routes every `showsUserInterface: false`
/// action to THIS entry point (a separate isolate) on Android — regardless
/// of whether the app's foreground engine is running. The separate isolate
/// cannot reach the live [BackgroundService], so dismissal, snooze and
/// backstop re-arm all happen here against a fresh plugin instance and the
/// persisted [ReminderStore].
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  final plugin = FlutterLocalNotificationsPlugin();
  handleStillDrivingBackgroundAction(
    response,
    cancel: plugin.cancel,
    store: ReminderStore(),
    scheduleBackstop: (destination, triggerTime) {
      tz.initializeTimeZones();
      return scheduleStillDrivingBackstop(plugin, destination, triggerTime);
    },
  );
}

/// Registers the far-out "Vieläkö ajat?" platform backstop (id 3). Top-level
/// so both [NotificationService.scheduleTimeBasedReminder] (main isolate)
/// and [notificationTapBackground] (background isolate, after an "Ajan yhä"
/// tap) build the identical notification.
Future<void> scheduleStillDrivingBackstop(
  FlutterLocalNotificationsPlugin plugin,
  String destination,
  DateTime triggerTime,
) async {
  final scheduledDate = tz.TZDateTime.from(triggerTime, tz.local);

  const androidDetails = AndroidNotificationDetails(
    'kilometrikorvaus_reminder',
    'Muistutukset',
    channelDescription: 'Aikaperusteinen muistutus',
    importance: Importance.high,
    priority: Priority.high,
    actions: [
      AndroidNotificationAction(
        NotificationService._arrivedActionId,
        'Olen perillä',
        showsUserInterface: true,
      ),
      // See the comment in showArrivalReminder — "Ajan yhä" is handled
      // entirely by the background isolate.
      AndroidNotificationAction(
        NotificationService.stillDrivingActionId,
        'Ajan yhä',
        showsUserInterface: false,
        cancelNotification: true,
      ),
    ],
  );

  await plugin.zonedSchedule(
    NotificationService.scheduledReminderId,
    'Vieläkö ajat?',
    'Matka kohteeseen $destination on yhä kesken.',
    scheduledDate,
    const NotificationDetails(android: androidDetails),
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
  );
}

class NotificationService {
  static const _channelId = 'kilometrikorvaus_driving';
  static const _channelName = 'Ajo käynnissä';
  static const _arrivedActionId = 'arrived';

  /// Action id for the "Ajan yhä" (still-driving) button. Public so the
  /// integration harness can drive the real response-routing path instead of
  /// poking [BackgroundService] directly.
  static const stillDrivingActionId = 'still_driving';
  static const _startTripActionId = 'start_trip';
  static const _dismissActionId = 'dismiss';
  static const _endTripActionId = 'end_trip';

  /// Platform notification ids. Public so the same ids are shared by the
  /// background dismissal handler and tests rather than duplicated as magic
  /// numbers.
  static const drivingNotificationId = 1;
  static const arrivalReminderId = 2;
  static const scheduledReminderId = 3;
  static const _tripDetectionId = 4;
  static const _tripEndDetectionId = 5;

  final FlutterLocalNotificationsPlugin _plugin;
  void Function()? onArrived;
  void Function()? onStillDriving;
  void Function()? onStartTrip;
  void Function()? onEndTrip;

  NotificationService()
      : _plugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    tz.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    // When an action button with showsUserInterface: true is tapped while the
    // app is terminated, it cold-launches the app instead of hitting the
    // foreground handler. Capture that response so it can be replayed once the
    // app's callbacks are wired up (see flushPendingLaunchAction).
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      _pendingLaunchResponse = launchDetails!.notificationResponse;
    }
  }

  NotificationResponse? _pendingLaunchResponse;

  /// Replays a notification action that cold-launched the app. Call this once,
  /// after onArrived/onStillDriving/etc. have been assigned.
  void flushPendingLaunchAction() {
    final pending = _pendingLaunchResponse;
    if (pending != null) {
      _pendingLaunchResponse = null;
      _onNotificationResponse(pending);
    }
  }

  Future<bool> requestPermission() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      return await androidPlugin.requestNotificationsPermission() ?? false;
    }
    return true;
  }

  void _onNotificationResponse(NotificationResponse response) {
    if (response.actionId == _arrivedActionId) {
      onArrived?.call();
    } else if (response.actionId == stillDrivingActionId) {
      onStillDriving?.call();
    } else if (response.actionId == _startTripActionId) {
      onStartTrip?.call();
    } else if (response.actionId == _endTripActionId) {
      onEndTrip?.call();
    }
  }

  Future<void> showDrivingNotification(TripLeg leg) async {
    final destination = leg.endLocation ?? leg.routeDescription ?? 'määränpää';
    final routeInfo = leg.routeDescription ?? '${leg.startLocation} → $destination';
    final body = '$routeInfo · ${leg.kmDriven.toStringAsFixed(0)} km\n'
        'Aloitettu: ${_formatTime(leg.startTime)} · Mittari: ${leg.startOdometer} km';

    final bigTextStyle = BigTextStyleInformation(
      body,
      htmlFormatBigText: true,
      contentTitle: 'Ajo käynnissä: $destination',
    );

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Näyttää aktiivisen ajolegin',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      styleInformation: bigTextStyle,
      actions: [
        const AndroidNotificationAction(
          _arrivedActionId,
          'Olen perillä',
          showsUserInterface: true,
        ),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: false,
    );

    await _plugin.show(
      drivingNotificationId,
      'Ajo käynnissä: $destination',
      routeInfo,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  Future<void> showArrivalReminder(String destination) async {
    const androidDetails = AndroidNotificationDetails(
      'kilometrikorvaus_reminder',
      'Muistutukset',
      channelDescription: 'Muistutus saapumisesta',
      importance: Importance.high,
      priority: Priority.high,
      actions: [
        AndroidNotificationAction(
          _arrivedActionId,
          'Olen perillä',
          showsUserInterface: true,
        ),
        // "Ajan yhä" must NOT cold-launch the app — tapping it just defers
        // the reminder. With showsUserInterface=false the tap is delivered
        // to the background isolate (notificationTapBackground) on Android
        // in ALL app states — it never reaches _onNotificationResponse, even
        // with the app in the foreground. cancelNotification removes the
        // tapped copy natively; handleStillDrivingBackgroundAction then
        // dismisses both reminder ids, persists the snooze the main-isolate
        // poll & proximity checks honour, and re-arms the platform backstop.
        AndroidNotificationAction(
          stillDrivingActionId,
          'Ajan yhä',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    await _plugin.show(
      arrivalReminderId,
      'Oletko perillä?',
      'Saavuitko kohteeseen: $destination?',
      const NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> scheduleTimeBasedReminder(
    String destination,
    DateTime triggerTime,
  ) async {
    await scheduleStillDrivingBackstop(_plugin, destination, triggerTime);
  }

  Future<void> cancelDrivingNotification() async {
    await _plugin.cancel(drivingNotificationId);
  }

  Future<void> cancelReminders() async {
    await _plugin.cancel(arrivalReminderId);
    await _plugin.cancel(scheduledReminderId);
  }

  /// Cancels only the pre-scheduled platform reminder (id 3), leaving any
  /// already-shown "Oletko perillä?" notification (id 2) in place. Used when
  /// the in-process timer fires while the user is still in_vehicle and we
  /// want to defer the reminder by rescheduling — without letting the
  /// platform fire its own copy at the original time.
  Future<void> cancelScheduledReminder() async {
    await _plugin.cancel(scheduledReminderId);
  }

  /// Show notification when potential driving is detected.
  Future<void> showTripDetectionNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'kilometrikorvaus_detection',
      'Ajontunnistus',
      channelDescription: 'Ilmoittaa mahdollisesta ajosta',
      importance: Importance.high,
      priority: Priority.high,
      actions: [
        AndroidNotificationAction(
          _startTripActionId,
          'Aloita ajo',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          _dismissActionId,
          'Ei nyt',
          showsUserInterface: false,
        ),
      ],
    );

    await _plugin.show(
      _tripDetectionId,
      'Ajatko autoa?',
      'GPS havaitsi liikettä. Aloitetaanko ajokirjanpito?',
      const NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// Show notification when vehicle has stopped after driving.
  Future<void> showTripEndDetectionNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'kilometrikorvaus_detection',
      'Ajontunnistus',
      channelDescription: 'Ilmoittaa mahdollisesta saapumisesta',
      importance: Importance.high,
      priority: Priority.high,
      actions: [
        AndroidNotificationAction(
          _endTripActionId,
          'Lopeta ajo',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          _dismissActionId,
          'Ei nyt',
          showsUserInterface: false,
        ),
      ],
    );

    await _plugin.show(
      _tripEndDetectionId,
      'Saavuitko perille?',
      'GPS havaitsee, että olet pysähtynyt. Lopetetaanko ajo?',
      const NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// Cancel detection notifications.
  Future<void> cancelDetectionNotifications() async {
    await _plugin.cancel(_tripDetectionId);
    await _plugin.cancel(_tripEndDetectionId);
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
