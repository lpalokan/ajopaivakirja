import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Given stopping the trip location stream fails once
///
/// The one failure the guarded teardown cannot recover from on its own: the
/// GPS teardown itself. The next attempt succeeds, so the scenario is really
/// asking whether anything ever makes a second attempt.
Future<void> stoppingTheTripLocationStreamFailsOnce(WidgetTester tester) async {
  failNextStopMonitoring();
}
