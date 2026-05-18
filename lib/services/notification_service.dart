import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../models/trip_leg.dart';

/// Handles notification action taps delivered to the background isolate.
///
/// flutter_local_notifications only dispatches action-button taps to Dart at
/// all when this callback is registered. Actions that need app state/UI use
/// `showsUserInterface: true`, so they launch the app and are re-delivered to
/// the foreground handler; this entry point just needs to exist so the
/// plugin's action receiver is wired up (and to swallow no-UI actions).
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {}

class NotificationService {
  static const _channelId = 'kilometrikorvaus_driving';
  static const _channelName = 'Ajo käynnissä';
  static const _arrivedActionId = 'arrived';
  static const _stillDrivingActionId = 'still_driving';
  static const _startTripActionId = 'start_trip';
  static const _dismissActionId = 'dismiss';
  static const _endTripActionId = 'end_trip';

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
    } else if (response.actionId == _stillDrivingActionId) {
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
      1,
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
        AndroidNotificationAction(
          _stillDrivingActionId,
          'Ajan yhä',
          showsUserInterface: true,
        ),
      ],
    );

    await _plugin.show(
      2,
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
    final scheduledDate = tz.TZDateTime.from(triggerTime, tz.local);

    const androidDetails = AndroidNotificationDetails(
      'kilometrikorvaus_reminder',
      'Muistutukset',
      channelDescription: 'Aikaperusteinen muistutus',
      importance: Importance.high,
      priority: Priority.high,
      actions: [
        AndroidNotificationAction(
          _arrivedActionId,
          'Olen perillä',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          _stillDrivingActionId,
          'Ajan yhä',
          showsUserInterface: true,
        ),
      ],
    );

    await _plugin.zonedSchedule(
      3,
      'Vieläkö ajat?',
      'Matka kohteeseen $destination on yhä kesken.',
      scheduledDate,
      const NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelDrivingNotification() async {
    await _plugin.cancel(1);
  }

  Future<void> cancelReminders() async {
    await _plugin.cancel(2);
    await _plugin.cancel(3);
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
      4,
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
      5,
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
    await _plugin.cancel(4);
    await _plugin.cancel(5);
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
