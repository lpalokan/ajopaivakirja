import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/models/app_settings.dart';

void main() {
  group('AppSettings serialization', () {
    test('toMap/fromMap round-trips all fields', () {
      const settings = AppSettings(
        homeLocation: 'Kotiosoite',
        kmRate: 0.59,
        allowance6h: 22.0,
        allowance10h: 45.0,
        sheetId: 'abc123',
        sheetTab: 'Matkat',
        driverName: 'Testaaja',
        debugLogging: true,
      );
      final restored = AppSettings.fromMap(settings.toMap());

      expect(restored.homeLocation, 'Kotiosoite');
      expect(restored.kmRate, 0.59);
      expect(restored.allowance6h, 22.0);
      expect(restored.allowance10h, 45.0);
      expect(restored.sheetId, 'abc123');
      expect(restored.sheetTab, 'Matkat');
      expect(restored.driverName, 'Testaaja');
      expect(restored.debugLogging, true);
    });

    test('fromMap applies defaults for missing or invalid values', () {
      final settings = AppSettings.fromMap({'km_rate': 'not-a-number'});
      expect(settings.kmRate, 0.57);
      expect(settings.homeLocation, 'Koti');
      expect(settings.allowance6h, 25.0);
      expect(settings.allowance10h, 54.0);
      expect(settings.sheetTab, 'Taulukko1');
      expect(settings.debugLogging, false);
    });

    test('debug_logging encodes as 1/0', () {
      expect(const AppSettings(debugLogging: true).toMap()['debug_logging'],
          '1');
      expect(const AppSettings(debugLogging: false).toMap()['debug_logging'],
          '0');
    });

    test('fromJson coerces non-string values', () {
      final settings = AppSettings.fromJson({
        'km_rate': 0.6,
        'debug_logging': '1',
        'home_location': 'X',
      });
      expect(settings.kmRate, 0.6);
      expect(settings.debugLogging, true);
      expect(settings.homeLocation, 'X');
    });

    test('copyWith overrides only provided fields', () {
      const base = AppSettings(homeLocation: 'A', kmRate: 0.5);
      final updated = base.copyWith(kmRate: 0.7);
      expect(updated.kmRate, 0.7);
      expect(updated.homeLocation, 'A');
    });
  });
}
