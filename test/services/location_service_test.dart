import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kilometrikorvaus/models/app_settings.dart';
import 'package:kilometrikorvaus/services/location_service.dart';

/// [LocationService] with the two platform touch points replaced: the
/// permission check and the position stream. Everything else — including the
/// decision of WHICH location settings a trip runs on, which is what issue #77
/// is about — is the production code path.
class _TestableLocationService extends LocationService {
  _TestableLocationService(this._feed);

  final Stream<Position> _feed;

  LocationSettings? settingsUsed;
  int openCount = 0;

  @override
  Future<bool> hasPermissionGranted() async => true;

  @override
  Stream<Position> openTripPositionStream(LocationSettings settings) {
    settingsUsed = settings;
    openCount++;
    return _feed;
  }

  LocationSettings? idleSettingsUsed;
  int idleOpenCount = 0;

  @override
  Stream<Position> openIdlePositionStream(LocationSettings settings) {
    idleSettingsUsed = settings;
    idleOpenCount++;
    return _feed;
  }
}

Position _fix({double speed = 25.0}) => Position(
  latitude: 60.0,
  longitude: 25.0,
  timestamp: DateTime.now(),
  accuracy: 5.0,
  altitude: 0.0,
  altitudeAccuracy: 0.0,
  heading: 0.0,
  headingAccuracy: 0.0,
  speed: speed,
  speedAccuracy: 0.0,
);

void main() {
  group('tripLocationSettings', () {
    test('runs a location foreground service on Android', () {
      final settings = LocationService.tripLocationSettings(android: true);

      expect(settings, isA<AndroidSettings>());
      final config = (settings as AndroidSettings).foregroundNotificationConfig;
      expect(
        config,
        isNotNull,
        reason:
            'Without a foregroundNotificationConfig geolocator never starts '
            'its foreground service, and Android stops delivering location to '
            'a whileInUse app as soon as the screen is locked (issue #77).',
      );
      expect(config!.notificationTitle, isNotEmpty);
      expect(config.notificationText, isNotEmpty);
      // The system may otherwise sleep and deliver a burst of stale positions
      // on wake, which a recency check cannot use.
      expect(config.enableWakeLock, isTrue);
      expect(LocationService.isForegroundBacked(settings), isTrue);
    });

    test('falls back to plain settings off Android', () {
      final settings = LocationService.tripLocationSettings(android: false);

      expect(settings, isNot(isA<AndroidSettings>()));
      expect(LocationService.isForegroundBacked(settings), isFalse);
    });

    test('keeps the trip distance filter on both platforms', () {
      expect(
        LocationService.tripLocationSettings(android: true).distanceFilter,
        LocationService.tripDistanceFilterMeters,
      );
      expect(
        LocationService.tripLocationSettings(android: false).distanceFilter,
        LocationService.tripDistanceFilterMeters,
      );
    });
  });

  group('idleLocationSettings', () {
    test('does not run a foreground service', () {
      final settings = LocationService.idleLocationSettings();

      expect(
        LocationService.isForegroundBacked(settings),
        isFalse,
        reason:
            'the home screen\'s "where am I" stream is cancelled the moment '
            'the app is backgrounded, so it must never cost the user an '
            'ongoing notification or a wake lock',
      );
    });

    test('uses the coarse idle distance filter', () {
      expect(
        LocationService.idleLocationSettings().distanceFilter,
        LocationService.idleDistanceFilterMeters,
      );
      expect(
        LocationService.idleLocationSettings().accuracy,
        LocationAccuracy.medium,
      );
    });
  });

  group('watchIdlePosition', () {
    late StreamController<Position> feed;
    late _TestableLocationService service;

    setUp(() {
      feed = StreamController<Position>.broadcast();
      service = _TestableLocationService(feed.stream);
    });

    tearDown(() async => feed.close());

    test('opens the platform stream with the idle settings', () async {
      final seen = <Position>[];
      final sub = service.watchIdlePosition().listen(seen.add);

      feed.add(_fix(speed: 0));
      await Future<void>.delayed(Duration.zero);

      expect(service.idleOpenCount, 1);
      expect(
        LocationService.isForegroundBacked(service.idleSettingsUsed!),
        isFalse,
      );
      expect(seen, hasLength(1));
      await sub.cancel();
    });

    test(
      'a stream error pauses the watch instead of taking the screen down',
      () async {
        final seen = <Position>[];
        Object? escaped;
        final sub = service.watchIdlePosition().listen(
          seen.add,
          onError: (Object e) => escaped = e,
        );

        feed.addError(StateError('no fix'));
        feed.add(_fix(speed: 0));
        await Future<void>.delayed(Duration.zero);

        expect(escaped, isNull);
        expect(seen, hasLength(1));
        await sub.cancel();
      },
    );
  });

  group('startMonitoringDestination', () {
    late StreamController<Position> feed;
    late _TestableLocationService service;

    setUp(() {
      feed = StreamController<Position>.broadcast();
      service = _TestableLocationService(feed.stream);
    });

    tearDown(() async {
      await service.stopMonitoring();
      await feed.close();
    });

    test(
      'opens the trip stream with the foreground-service settings',
      () async {
        await service.startMonitoringDestination(
          'Koti',
          const AppSettings(),
          (_) async {},
        );

        expect(service.openCount, 1);
        expect(service.settingsUsed, isNotNull);
        expect(
          LocationService.isForegroundBacked(
            LocationService.tripLocationSettings(android: true),
          ),
          isTrue,
        );
        expect(service.isMonitoring, isTrue);
      },
    );

    test('republishes incoming fixes on positionStream', () async {
      final seen = <Position>[];
      final sub = service.positionStream.listen(seen.add);

      await service.startMonitoringDestination(
        'Koti',
        const AppSettings(),
        (_) async {},
      );
      feed.add(_fix(speed: 25.0));
      feed.add(_fix(speed: 24.0));
      await Future<void>.delayed(Duration.zero);

      expect(seen.map((p) => p.speed), [25.0, 24.0]);
      await sub.cancel();
    });

    test('stopMonitoring tears the stream (and its service) down', () async {
      final seen = <Position>[];
      final sub = service.positionStream.listen(seen.add);

      await service.startMonitoringDestination(
        'Koti',
        const AppSettings(),
        (_) async {},
      );
      await service.stopMonitoring();
      feed.add(_fix());
      await Future<void>.delayed(Duration.zero);

      expect(service.isMonitoring, isFalse);
      expect(
        seen,
        isEmpty,
        reason: 'a stopped trip must not keep the foreground service alive',
      );
      await sub.cancel();
    });

    test('restarting monitoring does not leak the previous stream', () async {
      await service.startMonitoringDestination(
        'Koti',
        const AppSettings(),
        (_) async {},
      );
      await service.startMonitoringDestination(
        'Työ',
        const AppSettings(),
        (_) async {},
      );

      expect(service.openCount, 2);
      expect(service.isMonitoring, isTrue);
    });
  });
}
