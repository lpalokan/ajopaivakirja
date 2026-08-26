import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/main.dart' show NumeralTypography;
import 'package:kilometrikorvaus/widgets/start_card.dart';

/// The home screen's shape in miniature: a StartCard whose odometer notifier
/// is also watched by a sibling built earlier in the same frame — the route
/// preview card, in the real screen.
Widget _harness({
  required GlobalKey key,
  required ValueNotifier<int?> notifier,
  int? initialOdometer,
}) => MaterialApp(
  // StartCard reads the app's numeral typography extension.
  theme: ThemeData(extensions: [NumeralTypography.standard()]),
  home: Scaffold(
    body: Column(
      children: [
        ValueListenableBuilder<int?>(
          valueListenable: notifier,
          builder: (context, value, _) => Text('odo: ${value ?? '-'}'),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: StartCard(
              key: key,
              initialOdometer: initialOdometer,
              odometerNotifier: notifier,
              onStart: () {},
              locationChip: const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    ),
  ),
);

void main() {
  testWidgets('a new initialOdometer does not mark a sibling dirty mid-build', (
    tester,
  ) async {
    // Regression: didUpdateWidget wrote the controller during the build
    // phase, which notified the odometer ValueNotifier synchronously and
    // called setState on the already-built sibling — "setState() or
    // markNeedsBuild() called during build". It surfaces whenever the last
    // leg changes while the home screen rebuilds, which is exactly what
    // finishing a trip does.
    final key = GlobalKey<StartCardState>();
    final notifier = ValueNotifier<int?>(null);
    addTearDown(notifier.dispose);

    await tester.pumpWidget(
      _harness(key: key, notifier: notifier, initialOdometer: 1000),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      _harness(key: key, notifier: notifier, initialOdometer: 1108),
    );
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason: 'rebuilding with a new initialOdometer must not throw',
    );
    expect(find.text('odo: 1108'), findsOneWidget);
    expect(key.currentState?.odometerValue, 1108);
  });
}
