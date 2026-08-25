import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kilometrikorvaus/main.dart';
import 'package:kilometrikorvaus/models/location_zone.dart';
import 'package:kilometrikorvaus/providers/position_provider.dart';
import 'package:kilometrikorvaus/services/location_service.dart';
import 'package:kilometrikorvaus/widgets/location_chip.dart';

/// [LocationService] with every platform touch point replaced: permission,
/// the one-shot fixes, the idle stream, and the zone lookup (which would
/// otherwise need sqflite). Everything the chip and
/// [CurrentPositionNotifier] actually do is the production path.
class _FakeLocationService extends LocationService {
  _FakeLocationService({this.zones = const []});

  List<LocationZone> zones;
  bool permissionGranted = true;
  Position? current;

  final StreamController<Position> idle =
      StreamController<Position>.broadcast();

  @override
  Future<bool> hasPermissionGranted() async => permissionGranted;

  @override
  Future<Position?> getCurrentPosition({
    Duration timeLimit = const Duration(seconds: 15),
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) async => permissionGranted ? current : null;

  @override
  Future<Position?> getLastKnownPosition() async =>
      permissionGranted ? current : null;

  @override
  Stream<Position> watchIdlePosition() => idle.stream;

  @override
  Future<List<ZoneMatch>> findNearbyZones(Position position) async =>
      LocationService.matchZones(zones, position.latitude, position.longitude);
}

Position _fix(double latitude, double longitude) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: DateTime(2026, 8, 24),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

LocationZone _zone(String name, double latitude, double longitude) =>
    LocationZone(
      name: name,
      latitude: latitude,
      longitude: longitude,
      createdAt: '2026-01-01T00:00:00',
    );

Future<ProviderContainer> _pumpChip(
  WidgetTester tester,
  _FakeLocationService service, {
  String? fallbackLabel = 'Koti',
  void Function(String)? onChanged,
}) async {
  final container = ProviderContainer(
    overrides: [locationServiceProvider.overrideWithValue(service)],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: LocationChip(
            fallbackLabel: fallbackLabel,
            onChanged: onChanged ?? (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('names the known location the fix lands on', (tester) async {
    final service = _FakeLocationService(
      zones: [_zone('Toimisto', 60.2, 24.65)],
    )..current = _fix(60.2, 24.65);

    await _pumpChip(tester, service);

    expect(find.text('Toimisto'), findsOneWidget);
    expect(find.text('Koti'), findsNothing);
  });

  testWidgets('follows the driver instead of showing the first fix forever', (
    tester,
  ) async {
    // The regression this whole change exists for: the chip used to resolve
    // once in initState and never again.
    final service = _FakeLocationService(
      zones: [_zone('Toimisto', 60.2, 24.65), _zone('Varasto', 60.4, 25.0)],
    )..current = _fix(60.2, 24.65);

    final container = await _pumpChip(tester, service);
    container.read(currentPositionProvider.notifier).startIdleWatch();
    expect(find.text('Toimisto'), findsOneWidget);

    service.idle.add(_fix(60.4, 25.0));
    await tester.pumpAndSettle();

    expect(find.text('Varasto'), findsOneWidget);
    expect(find.text('Toimisto'), findsNothing);
  });

  testWidgets('a known location 300 m away still names the position', (
    tester,
  ) async {
    final service = _FakeLocationService(
      zones: [_zone('Toimisto', 60.2, 24.65)],
    )..current = _fix(60.2027, 24.65);

    await _pumpChip(tester, service);

    expect(find.text('Toimisto'), findsOneWidget);
  });

  testWidgets('falls back once the nearest known location is out of reach', (
    tester,
  ) async {
    final service = _FakeLocationService(
      zones: [_zone('Toimisto', 60.2, 24.65)],
    )..current = _fix(60.21, 24.65);

    await _pumpChip(tester, service);

    expect(find.text('Toimisto'), findsNothing);
    expect(find.text('Koti'), findsOneWidget);
    expect(find.textContaining('edellinen'), findsOneWidget);
  });

  testWidgets('says when there is no location permission', (tester) async {
    final service =
        _FakeLocationService(zones: [_zone('Toimisto', 60.2, 24.65)])
          ..permissionGranted = false
          ..current = _fix(60.2, 24.65);

    await _pumpChip(tester, service);

    expect(find.text('Toimisto'), findsNothing);
    expect(find.textContaining('ei sijaintilupaa'), findsOneWidget);
  });

  testWidgets('hands the resolved place to the parent once', (tester) async {
    final reported = <String>[];
    final service = _FakeLocationService(
      zones: [_zone('Toimisto', 60.2, 24.65)],
    )..current = _fix(60.2, 24.65);

    final container = await _pumpChip(tester, service, onChanged: reported.add);
    // A rebuild for an unrelated reason must not re-notify.
    container.read(currentPositionProvider.notifier).startIdleWatch();
    service.idle.add(_fix(60.2001, 24.65));
    await tester.pumpAndSettle();

    expect(reported, ['Toimisto']);
  });
}
