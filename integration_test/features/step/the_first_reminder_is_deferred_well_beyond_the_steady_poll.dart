import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Given the first reminder is deferred well beyond the steady poll
Future<void> theFirstReminderIsDeferredWellBeyondTheSteadyPoll(
  WidgetTester tester,
) async {
  deferFirstReminderFarOut();
}
