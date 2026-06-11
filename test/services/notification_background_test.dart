import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/services/notification_service.dart';
import 'package:kilometrikorvaus/services/reminder_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Covers the background-isolate path for the "Ajan yhä" (still-driving)
/// notification action.
///
/// On Android this is the ONLY path the action is ever delivered to —
/// `showsUserInterface: false` actions go to the background isolate even
/// while the app is in the foreground — so everything the tap must do
/// (dismiss both reminders, persist the snooze, re-arm the platform
/// backstop) is pinned here on the host VM via the pure
/// `handleStillDrivingBackgroundAction` seam.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  NotificationResponse action(String? actionId) => NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: actionId,
      );

  late ReminderStore store;
  late List<int> cancelled;
  late List<(String, DateTime)> scheduled;

  Future<void> handle(
    NotificationResponse response, {
    Duration snoozeDuration = stillDrivingSnoozeDuration,
  }) {
    return handleStillDrivingBackgroundAction(
      response,
      cancel: (id) async => cancelled.add(id),
      store: store,
      scheduleBackstop: (destination, triggerTime) async =>
          scheduled.add((destination, triggerTime)),
      snoozeDuration: snoozeDuration,
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = ReminderStore();
    cancelled = [];
    scheduled = [];
  });

  group('handleStillDrivingBackgroundAction', () {
    test('dismisses both the arrival reminder and the platform backstop',
        () async {
      // Either id can be the notification actually on screen: id 2 from the
      // in-process poll, id 3 when the process was killed and the platform
      // backstop fired. The tap must take down whichever is visible.
      await handle(action(NotificationService.stillDrivingActionId));
      expect(cancelled, contains(NotificationService.arrivalReminderId));
      expect(cancelled, contains(NotificationService.scheduledReminderId));
    });

    test('persists a snooze deadline for the main-isolate reminder loop',
        () async {
      final before = DateTime.now();
      await handle(action(NotificationService.stillDrivingActionId));
      final after = DateTime.now();

      final snoozedUntil = await store.snoozedUntil();
      expect(snoozedUntil, isNotNull);
      // The store persists epoch milliseconds, so compare at that precision.
      final snoozeMs = stillDrivingSnoozeDuration.inMilliseconds;
      expect(
        snoozedUntil!.millisecondsSinceEpoch,
        greaterThanOrEqualTo(before.millisecondsSinceEpoch + snoozeMs),
        reason: 'snooze must extend at least stillDrivingSnoozeDuration out',
      );
      expect(
        snoozedUntil.millisecondsSinceEpoch,
        lessThanOrEqualTo(after.millisecondsSinceEpoch + snoozeMs),
        reason:
            'snooze must not extend beyond now + stillDrivingSnoozeDuration',
      );
    });

    test('re-arms the platform backstop with the stored destination',
        () async {
      // Cancelling id 3 also unschedules a pending backstop; when the app
      // process is dead that schedule is the only future re-prompt, so the
      // tap must register a fresh one.
      await store.setDestination('Koti');
      final before = DateTime.now();
      await handle(action(NotificationService.stillDrivingActionId));

      expect(scheduled, hasLength(1));
      expect(scheduled.single.$1, 'Koti');
      final triggerTime = scheduled.single.$2;
      expect(
        triggerTime.isBefore(before.add(stillDrivingBackstopRearmDuration)),
        isFalse,
      );
    });

    test('falls back to a generic destination when none is stored', () async {
      await handle(action(NotificationService.stillDrivingActionId));
      expect(scheduled, hasLength(1));
      expect(scheduled.single.$1, 'määränpää');
    });

    test('ignores other action ids', () async {
      await handle(action('arrived'));
      await handle(action(null));
      expect(cancelled, isEmpty);
      expect(scheduled, isEmpty);
      expect(await store.snoozedUntil(), isNull);
    });
  });

  group('ReminderStore', () {
    test('round-trips and clears its state', () async {
      final until = DateTime.fromMillisecondsSinceEpoch(
        DateTime.now().millisecondsSinceEpoch + 60000,
      );
      await store.setSnoozedUntil(until);
      await store.setDestination('Työ');
      expect(await store.snoozedUntil(), until);
      expect(await store.destination(), 'Työ');

      await store.clear();
      expect(await store.snoozedUntil(), isNull);
      expect(await store.destination(), isNull);
    });
  });
}
