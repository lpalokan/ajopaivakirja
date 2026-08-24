import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/models/location_zone.dart';
import 'package:kilometrikorvaus/models/route.dart';
import 'package:kilometrikorvaus/services/location_service.dart';
import 'package:kilometrikorvaus/services/nearby_routes.dart';

Route _route(
  String name, {
  required String start,
  String end = 'Muualle',
  int daysAgo = 0,
}) {
  final ts = DateTime(2026, 1, 10).subtract(Duration(days: daysAgo));
  return Route(
    id: name.hashCode,
    name: name,
    startLocation: start,
    endLocation: end,
    distanceKm: 10,
    createdAt: ts,
    updatedAt: ts,
  );
}

LocationZone _zone(String name, {double radius = 200}) => LocationZone(
  name: name,
  latitude: 60,
  longitude: 25,
  radiusMeters: radius,
  createdAt: '2026-01-01T00:00:00',
);

ZoneMatch _match(String name, double meters) =>
    ZoneMatch(zone: _zone(name), distanceMeters: meters);

void main() {
  group('matchZones', () {
    // 0.0027° of latitude is ~300 m; 0.01° is ~1.1 km.
    const lat = 60.2;
    const lon = 24.65;

    test('matches a zone the fix is standing in', () {
      final zones = [
        LocationZone(
          name: 'Koti',
          latitude: lat,
          longitude: lon,
          createdAt: '2026-01-01T00:00:00',
        ),
      ];

      final matches = LocationService.matchZones(zones, lat, lon);

      expect(matches, hasLength(1));
      expect(matches.first.zone.name, 'Koti');
      expect(matches.first.distanceMeters, lessThan(1));
    });

    test('matches a zone 300 m away even though its radius is 200 m', () {
      final zones = [
        LocationZone(
          name: 'Koti',
          latitude: lat,
          longitude: lon,
          radiusMeters: 200,
          createdAt: '2026-01-01T00:00:00',
        ),
      ];

      final matches = LocationService.matchZones(zones, lat + 0.0027, lon);

      expect(
        matches,
        hasLength(1),
        reason:
            'the driver is usually on the street outside the geofence, not '
            'standing in its centre',
      );
      expect(matches.first.distanceMeters, closeTo(300, 15));
    });

    test('does not match a zone 1.1 km away', () {
      final zones = [
        LocationZone(
          name: 'Koti',
          latitude: lat,
          longitude: lon,
          createdAt: '2026-01-01T00:00:00',
        ),
      ];

      expect(LocationService.matchZones(zones, lat + 0.01, lon), isEmpty);
    });

    test('a zone wider than the slack still matches from inside it', () {
      final zones = [
        LocationZone(
          name: 'Tehdasalue',
          latitude: lat,
          longitude: lon,
          radiusMeters: 2000,
          createdAt: '2026-01-01T00:00:00',
        ),
      ];

      final matches = LocationService.matchZones(zones, lat + 0.01, lon);

      expect(matches, hasLength(1));
    });

    test('orders matches nearest first', () {
      final zones = [
        LocationZone(
          name: 'Kauempi',
          latitude: lat + 0.0036,
          longitude: lon,
          createdAt: '2026-01-01T00:00:00',
        ),
        LocationZone(
          name: 'Lähempi',
          latitude: lat + 0.0009,
          longitude: lon,
          createdAt: '2026-01-01T00:00:00',
        ),
      ];

      final matches = LocationService.matchZones(zones, lat, lon);

      expect(matches.map((m) => m.zone.name), ['Lähempi', 'Kauempi']);
    });

    test('slack 0 keeps the strict in-radius behaviour arrival relies on', () {
      final zones = [
        LocationZone(
          name: 'Koti',
          latitude: lat,
          longitude: lon,
          radiusMeters: 200,
          createdAt: '2026-01-01T00:00:00',
        ),
      ];

      expect(
        LocationService.matchZones(zones, lat + 0.0027, lon, slackMeters: 0),
        isEmpty,
      );
    });
  });

  group('routesStartingNear', () {
    final toWork = _route('Töihin', start: 'Koti', end: 'Työ');
    final toHome = _route('Kotiin', start: 'Työ', end: 'Koti');

    test('keeps only the routes that start where we are', () {
      final nearby = routesStartingNear([toWork, toHome], [_match('Työ', 50)]);

      expect(nearby.map((r) => r.name), ['Kotiin']);
    });

    test('matches the place name case- and space-insensitively', () {
      final route = _route('Töihin', start: '  koti ');

      final nearby = routesStartingNear([route], [_match('Koti', 10)]);

      expect(nearby, hasLength(1));
    });

    test('orders by how close the start is', () {
      final near = _route('Läheltä', start: 'Piha');
      final far = _route('Kauempaa', start: 'Naapuri');

      final nearby = routesStartingNear(
        [far, near],
        [_match('Piha', 20), _match('Naapuri', 400)],
      );

      expect(nearby.map((r) => r.name), ['Läheltä', 'Kauempaa']);
    });

    test('breaks a tie on the same place by most recently driven', () {
      final older = _route('Vanha', start: 'Koti', daysAgo: 30);
      final newer = _route('Uusi', start: 'Koti', daysAgo: 1);

      final nearby = routesStartingNear([older, newer], [_match('Koti', 10)]);

      expect(nearby.map((r) => r.name), ['Uusi', 'Vanha']);
    });

    test('caps the list at the shortcut row size', () {
      final routes = [
        _route('A', start: 'Koti', daysAgo: 1),
        _route('B', start: 'Koti', daysAgo: 2),
        _route('C', start: 'Koti', daysAgo: 3),
      ];

      expect(routesStartingNear(routes, [_match('Koti', 10)]), hasLength(2));
    });

    test('is empty without a position, so home can fall back to recents', () {
      expect(routesStartingNear([toWork, toHome], const []), isEmpty);
    });

    test('is empty when no route starts at a known location nearby', () {
      expect(
        routesStartingNear([toWork, toHome], [_match('Mökki', 10)]),
        isEmpty,
      );
    });
  });
}
