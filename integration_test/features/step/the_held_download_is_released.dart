import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When the held download is released
Future<void> theHeldDownloadIsReleased(WidgetTester tester) async {
  await releaseHeldUpdateDownload(tester);
}
