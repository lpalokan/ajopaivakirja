import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kilometrikorvaus/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots on device and renders the home screen',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: KilometrikorvausApp()),
    );

    // HomeScreen.initState loads providers and the sqflite database via a
    // post-frame callback. Pump fixed frames instead of pumpAndSettle so the
    // smoke test does not hang on background timers/permission prompts.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    expect(find.text('Ajopäiväkirja'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
