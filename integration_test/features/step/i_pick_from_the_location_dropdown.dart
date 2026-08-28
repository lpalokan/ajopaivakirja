import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When I pick {string} from the location dropdown
Future<void> iPickFromTheLocationDropdown(
  WidgetTester tester,
  String value,
) async {
  await pickLocationOption(tester, value);
}
