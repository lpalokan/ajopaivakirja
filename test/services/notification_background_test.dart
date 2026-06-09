import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/services/notification_service.dart';

/// Covers the background-isolate dismissal path for the "Ajan yhä"
/// (still-driving) notification action.
///
/// This is the layer that the original bug slipped through: when the app's
/// foreground engine isn't running mid-drive, the tap lands in the separate
/// `notificationTapBackground` isolate — which used to be an empty stub, so
/// the reminder was never dismissed. The integration suite can't run that
/// isolate, so the contract is pinned here on the host VM via the pure
/// `handleStillDrivingBackgroundAction` seam.
void main() {
  NotificationResponse action(String? actionId) => NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: actionId,
      );

  group('handleStillDrivingBackgroundAction', () {
    test('dismisses the visible arrival reminder', () async {
      final cancelled = <int>[];
      await handleStillDrivingBackgroundAction(
        action(NotificationService.stillDrivingActionId),
        (id) async => cancelled.add(id),
      );
      expect(cancelled, contains(NotificationService.arrivalReminderId));
    });

    test('leaves the scheduled platform backstop intact', () async {
      // The OS-registered backstop is the only thing left to re-prompt a
      // driver whose process has been killed, so it must NOT be cancelled.
      final cancelled = <int>[];
      await handleStillDrivingBackgroundAction(
        action(NotificationService.stillDrivingActionId),
        (id) async => cancelled.add(id),
      );
      expect(cancelled, isNot(contains(NotificationService.scheduledReminderId)));
    });

    test('ignores other action ids', () async {
      final cancelled = <int>[];
      await handleStillDrivingBackgroundAction(
        action('arrived'),
        (id) async => cancelled.add(id),
      );
      await handleStillDrivingBackgroundAction(
        action(null),
        (id) async => cancelled.add(id),
      );
      expect(cancelled, isEmpty);
    });
  });
}
