import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../models/trip_leg.dart';

class NotificationService {
  static const _channelId = 'kilometrikorvaus_driving';
  static const _channelName = 'Ajo käynnissä';
  static const _arrivedActionId = 'arrived';
  static const _stillDrivingActionId = 'still_driving';

  final FlutterLocalNotificationsPlugin _plugin;
  Function? _onArrived;
  Function? _onStillDriving;

  NotificationService()
      : _plugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize({
    Function? onArrived,
    Function? onStillDriving,
  }) async {
    tz.initializeTimeZones();
    _onArrived = onArrived;
    _onStillDriving = onStillDriving;

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
    );
  }

  void _onNotificationResponse(NotificationResponse response) {
    if (response.actionId == _arrivedActionId) {
      _onArrived?.call();
    } else if (response.actionId == _stillDrivingActionId) {
      _onStillDriving?.call();
    }
  }

  Future<void> showDrivingNotification(TripLeg leg) async {
    final destination = leg.endLocation ?? leg.routeDescription ?? 'määränpää';
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Näyttää aktiivisen ajolegin',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
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
      'Aloitettu: ${_formatTime(leg.startTime)}',
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
          showsUserInterface: false,
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
          showsUserInterface: false,
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

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
