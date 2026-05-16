import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/widgets/odometer_dialog.dart';

Future<OdometerResult?> openDialog(
  WidgetTester tester, {
  String? relatedField,
}) async {
  late Future<OdometerResult?> future;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              future = showOdometerDialog(
                context: context,
                title: 'Aloita ajo',
                actionLabel: 'Aloita',
                relatedField: relatedField,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return future;
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
    final future = await openDialog(tester);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Aloita'));
    await tester.pumpAndSettle();

    final result = await future;
    expect(result, isNotNull);
    expect(result!.odometer, 123456);
    expect(result.purpose, isNull);
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
