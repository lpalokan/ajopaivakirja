// Headless BDD runner — runs the Gherkin integration suite on the flutter
// "tester" (host) WITHOUT an Android emulator. Needed because this machine
// has no KVM/hardware virtualization, so an Android AVD cannot run.
//
// It works because the harness fakes every platform service except sqflite
// (backed here by sqflite_common_ffi over the host's libsqlite3) and the
// geolocator plugin (mocked below, since TripDetectionService calls
// Geolocator statically rather than through the injected LocationService).
//
// Run all features:      flutter test tool/bdd_host_test.dart
// Run one scenario:      flutter test tool/bdd_host_test.dart --plain-name "<text>"
//
// Lives under tool/ (not integration_test/ or test/) so:
//   - flutter_tools doesn't route it to a device the way it does for files
//     under integration_test/, and
//   - the fast unit run `flutter test test/` doesn't pick it up.
//
// NOTE: the on-emulator suite (scripts/integration-report.sh) remains the
// source of truth. This headless runner is a no-emulator approximation
// (currently 90/92 scenarios). Known host-only gaps — all green on the
// emulator, see docs/testing.md → "Running without an emulator":
//   - the "app boots on device" smoke test (app_smoke_test.dart) is excluded
//     (its fixed-frame pumping trips the live binding's pending-frame assert);
//   - "Settings: Debug logging toggle reveals log actions" (tap misses on the
//     800x600 host surface);
//   - "Draft trips: Drafts excluded from CSV export" (host CSV file plumbing).
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../integration_test/features/accessibility_test.dart' as accessibility;
import '../integration_test/features/ad_hoc_driving_test.dart' as ad_hoc_driving;
import '../integration_test/features/calculations_test.dart' as calculations;
import '../integration_test/features/drafts_test.dart' as drafts;
import '../integration_test/features/driving_test.dart' as driving;
import '../integration_test/features/history_test.dart' as history;
import '../integration_test/features/home_context_test.dart' as home_context;
import '../integration_test/features/home_ux_test.dart' as home_ux;
import '../integration_test/features/navigation_test.dart' as navigation;
import '../integration_test/features/route_management_test.dart'
    as route_management;
import '../integration_test/features/seeded_routes_test.dart' as seeded_routes;
import '../integration_test/features/settings_test.dart' as settings;
import '../integration_test/features/update_check_test.dart' as update_check;

void _installPluginMocks() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // TripDetectionService talks to Geolocator statically (not through the
  // faked LocationService), so on the host tester its position stream throws
  // MissingPluginException. Mock the plugin's channels to keep detection inert.
  const geo = MethodChannel('flutter.baseflow.com/geolocator');
  messenger.setMockMethodCallHandler(geo, (call) async {
    switch (call.method) {
      case 'isLocationServiceEnabled':
        return true;
      case 'checkPermission':
      case 'requestPermission':
        return 1; // LocationPermission.denied — keeps detection inert
      default:
        return null;
    }
  });
  const geoUpdates = EventChannel('flutter.baseflow.com/geolocator_updates');
  messenger.setMockStreamHandler(
    geoUpdates,
    MockStreamHandler.inline(onListen: (args, sink) {}),
  );

  // path_provider has no host implementation; LogService, UpdateService and
  // the CSV/PDF export paths all ask it for a directory. Return real temp
  // dirs so those code paths work headless.
  final tmp = Directory.systemTemp.createTempSync('bdd_host_');
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  messenger.setMockMethodCallHandler(pathProvider, (call) async => tmp.path);

  // share_plus: swallow share sheets invoked by export/sync actions.
  const share = MethodChannel('dev.fluttercommunity.plus/share');
  messenger.setMockMethodCallHandler(share, (call) async => null);

  // shared_preferences backs ReminderStore (the cross-isolate "Ajan yhä"
  // snooze). The in-memory mock also starts every scenario from a clean
  // store, mirroring launchApp's per-scenario clear on the device.
  SharedPreferences.setMockInitialValues({});
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  setUp(_installPluginMocks);

  navigation.main();
  seeded_routes.main();
  route_management.main();
  settings.main();
  driving.main();
  ad_hoc_driving.main();
  history.main();
  home_context.main();
  home_ux.main();
  calculations.main();
  drafts.main();
  accessibility.main();
  update_check.main();
}
