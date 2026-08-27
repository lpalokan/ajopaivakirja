import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/widgets/location_autocomplete.dart';

const _suggestions = ['Asiakas', 'Koti', 'Työ'];

Widget _harness(TextEditingController controller) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 360,
        child: LocationAutocomplete(
          controller: controller,
          label: 'Lähtöpaikka',
          suggestions: _suggestions,
        ),
      ),
    ),
  ),
);

/// The trailing arrow. It is the only IconButton the field renders.
Finder get _arrow => find.descendant(
  of: find.byType(LocationAutocomplete),
  matching: find.byType(IconButton),
);

Finder _option(String label) => find.widgetWithText(MenuItemButton, label);

void main() {
  testWidgets('the arrow lists every location even when the field is filled', (
    tester,
  ) async {
    // The regression this guards: with the field pre-filled — editing a
    // route, or the "Muuta sijainti" dialog seeded with the current
    // location — the old RawAutocomplete filtered the option list by that
    // text, so the arrow offered "Koti" and nothing else.
    final controller = TextEditingController(text: 'Koti');
    addTearDown(controller.dispose);

    await tester.pumpWidget(_harness(controller));
    await tester.tap(_arrow);
    await tester.pumpAndSettle();

    for (final suggestion in _suggestions) {
      expect(
        _option(suggestion),
        findsOneWidget,
        reason: '"$suggestion" should be offered regardless of the field text',
      );
    }
  });

  testWidgets('picking an option writes it to the caller\'s controller', (
    tester,
  ) async {
    // Callers (the route dialog, the arrival dialog, LocationChip) read
    // controller.text when their save button is pressed, so a selection that
    // does not land there is a selection that never happened.
    final controller = TextEditingController(text: 'Koti');
    addTearDown(controller.dispose);

    await tester.pumpWidget(_harness(controller));
    await tester.tap(_arrow);
    await tester.pumpAndSettle();
    await tester.tap(_option('Työ'));
    await tester.pumpAndSettle();

    expect(controller.text, 'Työ');
  });

  testWidgets('a location that is not a known one can still be typed', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_harness(controller));
    await tester.enterText(find.byType(TextField), 'Varikko');
    await tester.pumpAndSettle();

    expect(controller.text, 'Varikko');
  });

  testWidgets('the caller can seed the field by writing to the controller', (
    tester,
  ) async {
    // How the integration harness sets an ad-hoc trip's start location, and
    // how every dialog pre-fills: the controller is the single source of
    // truth and the field must render what it holds.
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_harness(controller));
    controller.text = 'Asiakas';
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Asiakas',
    );
    expect(find.text('Asiakas'), findsOneWidget);
  });
}
