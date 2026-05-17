import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/widgets/odometer_dialog.dart';

/// Pumps a screen with a button that opens the dialog. The dialog result is
/// reported via [onResult] once the dialog is dismissed (we cannot return the
/// dialog future from an async helper — it would be flattened and awaited
/// before the test can interact with the dialog).
Future<void> openDialog(
  WidgetTester tester, {
  String? relatedField,
  void Function(OdometerResult?)? onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final result = await showOdometerDialog(
                context: context,
                title: 'Aloita ajo',
                actionLabel: 'Aloita',
                relatedField: relatedField,
              );
              onResult?.call(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty input shows validation error and keeps dialog open',
      (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('Aloita'));
    await tester.pumpAndSettle();

    expect(find.text('Syötä mittarilukema'), findsOneWidget);
    expect(find.text('Aloita ajo'), findsOneWidget); // dialog still shown
  });

  testWidgets('valid input returns the entered odometer', (tester) async {
    OdometerResult? result;
    var called = false;
    await openDialog(tester, onResult: (r) {
      result = r;
      called = true;
    });

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Aloita'));
    await tester.pumpAndSettle();

    expect(called, isTrue);
    expect(result, isNotNull);
    expect(result!.odometer, 123456);
    expect(result!.purpose, isNull);
  });

  testWidgets('no purpose field when relatedField is unset', (tester) async {
    await openDialog(tester);
    expect(find.widgetWithText(TextField, 'Tarkoitus'), findsNothing);
  });

  testWidgets('purpose field shown when relatedField is set', (tester) async {
    await openDialog(tester, relatedField: 'Tarkoitus');
    expect(find.widgetWithText(TextField, 'Tarkoitus'), findsOneWidget);
  });
}
