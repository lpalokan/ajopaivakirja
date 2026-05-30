import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:kilometrikorvaus/models/route.dart' as model;
import 'package:kilometrikorvaus/widgets/route_chip_row.dart';

model.Route _route({
  required int id,
  required String name,
  String start = 'Koti',
  String end = 'Työ',
  double km = 12.5,
}) {
  final ts = DateTime(2024, 1, 1);
  return model.Route(
    id: id,
    name: name,
    startLocation: start,
    endLocation: end,
    distanceKm: km,
    createdAt: ts,
    updatedAt: ts,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<model.Route> routes,
  int? selectedRouteId,
  void Function(model.Route)? onRouteSelected,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RouteChipRow(
          routes: routes,
          selectedRouteId: selectedRouteId,
          onRouteSelected: (r) => onRouteSelected?.call(r),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders one button per route with name and distance',
      (tester) async {
    await _pump(tester, routes: [
      _route(id: 1, name: 'Töihin', km: 54.0),
      _route(id: 2, name: 'Kotiin', km: 54.0),
    ]);

    expect(find.byType(RouteChip), findsNWidgets(2));
    expect(find.text('Töihin'), findsOneWidget);
    expect(find.text('Kotiin'), findsOneWidget);
    expect(find.textContaining('54.0 km'), findsNWidgets(2));
  });

  testWidgets('does not render the "Kaikki reitit" link', (tester) async {
    await _pump(tester, routes: [
      _route(id: 1, name: 'Töihin'),
      _route(id: 2, name: 'Kotiin'),
    ]);

    expect(find.textContaining('Kaikki reitit'), findsNothing);
  });

  testWidgets('tapping a button fires onRouteSelected with that route',
      (tester) async {
    model.Route? tapped;
    await _pump(
      tester,
      routes: [
        _route(id: 1, name: 'Töihin'),
        _route(id: 2, name: 'Kotiin'),
      ],
      onRouteSelected: (r) => tapped = r,
    );

    await tester.tap(find.text('Kotiin'));
    await tester.pump();

    expect(tapped, isNotNull);
    expect(tapped!.id, 2);
  });

  testWidgets('the selected route shows the redundant check-circle cue',
      (tester) async {
    await _pump(
      tester,
      routes: [
        _route(id: 1, name: 'Töihin'),
        _route(id: 2, name: 'Kotiin'),
      ],
      selectedRouteId: 1,
    );

    // Exactly one button is marked selected.
    expect(find.byIcon(Symbols.check_circle), findsOneWidget);
  });

  testWidgets('a single route still renders as one button', (tester) async {
    await _pump(tester, routes: [_route(id: 1, name: 'Töihin')]);

    expect(find.byType(RouteChip), findsOneWidget);
    expect(find.text('Töihin'), findsOneWidget);
  });
}
