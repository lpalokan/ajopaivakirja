import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/models/location_zone.dart';
import 'package:kilometrikorvaus/services/location_service.dart';

LocationZone zone(
  String name,
  double latitude,
  double longitude, {
  double radius = 200,
}) => LocationZone(
  name: name,
  latitude: latitude,
  longitude: longitude,
  radiusMeters: radius,
  createdAt: '2026-05-15T08:00:00.000',
);

/// Roughly 111.32 km to a degree of latitude.
double northOf(double latitude, double metres) => latitude + metres / 111320;

final _zones = [
  zone('Koti', 60.20, 24.65),
  zone('Työ', 60.40, 25.00),
  zone('Kauppa', 60.30, 24.80),
];

void main() {
  group('finding the destination', () {
    test('matches a place by name, ignoring case and padding', () {
      expect(LocationService.destinationZone(_zones, '  työ  ')?.name, 'Työ');
    });

    test('a destination the app has never learned matches nothing', () {
      expect(LocationService.destinationZone(_zones, 'Asiakas'), isNull);
      expect(LocationService.destinationZone(_zones, ''), isNull);
    });
  });

  group('arriving', () {
    test('a trip to work is an arrival at work', () {
      // The bug: the proximity check compared the destination against
      // settings.homeLocation and returned early unless they matched, so a
      // trip to anywhere but home never got a proximity reminder at all.
      expect(LocationService.hasArrivedAt(_zones, 'Työ', 60.40, 25.00), isTrue);
    });

    test('a trip home is still an arrival at home', () {
      expect(
        LocationService.hasArrivedAt(_zones, 'Koti', 60.20, 24.65),
        isTrue,
      );
    });

    test('driving past another known place is not an arrival', () {
      // Places are learned automatically now, so "any known zone counts"
      // would end a trip to work at the shop on the way.
      expect(
        LocationService.hasArrivedAt(_zones, 'Työ', 60.30, 24.80),
        isFalse,
        reason: 'standing at Kauppa is not arriving at Työ',
      );
    });

    test('grace extends the zone but does not replace it', () {
      final target = _zones[1];
      final justInside = northOf(
        target.latitude,
        target.radiusMeters + LocationService.arrivalGraceMeters - 20,
      );
      final wellOutside = northOf(
        target.latitude,
        target.radiusMeters + LocationService.arrivalGraceMeters + 200,
      );

      expect(
        LocationService.hasArrivedAt(_zones, 'Työ', justInside, 25.00),
        isTrue,
      );
      expect(
        LocationService.hasArrivedAt(_zones, 'Työ', wellOutside, 25.00),
        isFalse,
      );
    });

    test('a wide zone is matched on its own radius', () {
      final zones = [zone('Satama', 60.10, 24.90, radius: 1500)];
      final inside = northOf(60.10, 1200);

      expect(
        LocationService.hasArrivedAt(zones, 'Satama', inside, 24.90),
        isTrue,
      );
    });

    test('a destination with no known place never arrives', () {
      // Nothing to measure against, so the time-based reminder stays the only
      // one — better than a proximity prompt fired on a guess.
      expect(
        LocationService.hasArrivedAt(_zones, 'Asiakas', 60.40, 25.00),
        isFalse,
      );
      expect(
        LocationService.hasArrivedAt(const [], 'Koti', 60.20, 24.65),
        isFalse,
      );
    });
  });
}
