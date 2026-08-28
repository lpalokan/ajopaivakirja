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

/// The production layout: the field lives inside an AlertDialog, between
/// other fields, with its width coming from the dialog rather than from
/// itself.
Widget _dialogHarness(TextEditingController controller) => MaterialApp(
  home: Scaffold(
    body: AlertDialog(
      title: const Text('Muuta sijainti'),
      content: SizedBox(
        width: double.maxFinite,
        child: LocationAutocomplete(
          controller: controller,
          label: 'Sijainti',
          suggestions: _suggestions,
        ),
      ),
    ),
  ),
);

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

  testWidgets('tapping the field leaves the dialog buttons reachable', (
    tester,
  ) async {
    // The regression the emulator suite caught: a field that opens its menu
    // when tapped drops that menu over the dialog's actions, so the next tap
    // — aimed at "Käytä" — dismisses the menu instead of pressing the
    // button. Typing a location must not cost a tap on the primary action.
    final controller = TextEditingController(text: 'Koti');
    addTearDown(controller.dispose);
    var applied = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlertDialog(
            content: SizedBox(
              width: double.maxFinite,
              child: LocationAutocomplete(
                controller: controller,
                label: 'Sijainti',
                suggestions: _suggestions,
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => applied = true,
                child: const Text('Käytä'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(
      _option('Koti'),
      findsNothing,
      reason: 'tapping the field must not open the menu',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Käytä'));
    await tester.pumpAndSettle();

    expect(applied, isTrue);
  });

  testWidgets('lays out inside an AlertDialog', (tester) async {
    final controller = TextEditingController(text: 'Koti');
    addTearDown(controller.dispose);

    await tester.pumpWidget(_dialogHarness(controller));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('a controller write sticks while the menu is open', (
    tester,
  ) async {
    // Exactly what the integration harness does to set an ad-hoc trip's
    // start location: tap the field — which opens the menu — then write the
    // location straight onto the controller and read it back.
    final controller = TextEditingController(text: 'Koti');
    addTearDown(controller.dispose);

    await tester.pumpWidget(_dialogHarness(controller));
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    controller.text = 'Siba';
    controller.selection = const TextSelection.collapsed(offset: 4);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.text, 'Siba');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Siba',
    );
  });
}
