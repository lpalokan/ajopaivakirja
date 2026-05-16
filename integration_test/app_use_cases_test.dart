// End-to-end use-case tests, executed on a real Android emulator.
//
// The real app is pumped (KilometrikorvausApp) against the real on-device
// SQLite database. Only the external-world services (notifications, location,
// background, Google Sheets, ML-Kit OCR) are replaced with no-op fakes via
// Riverpod overrides, so no native permission dialogs or network are hit.
//
// The database is wiped before every test. In debug builds HomeScreen seeds
// two routes ("Töihin" Koti→Työ 54 km, "Kotiin" Työ→Koti 54 km), so every
// test starts from that deterministic state.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:kilometrikorvaus/main.dart';
import 'package:kilometrikorvaus/models/trip_leg.dart';
import 'package:kilometrikorvaus/services/background_service.dart';
import 'package:kilometrikorvaus/services/database_service.dart';
import 'package:kilometrikorvaus/services/location_service.dart';
import 'package:kilometrikorvaus/services/notification_service.dart';
import 'package:kilometrikorvaus/services/odometer_vision_service.dart';
import 'package:kilometrikorvaus/services/sheets_service.dart';

// ─── Fakes: keep the app off the platform/network ──────────────────────────

class _FakeNotificationService extends NotificationService {
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> showDrivingNotification(TripLeg leg) async {}
  @override
  Future<void> showArrivalReminder(String destination) async {}
  @override
  Future<void> scheduleTimeBasedReminder(String d, DateTime t) async {}
  @override
  Future<void> cancelDrivingNotification() async {}
  @override
  Future<void> cancelReminders() async {}
}

class _FakeLocationService extends LocationService {
  @override
  Future<bool> hasPermission() async => false;
  @override
  Future<void> startMonitoringDestination(
      String d, settings, NotificationService n) async {}
  @override
  Future<void> stopMonitoring() async {}
}

class _FakeBackgroundService extends BackgroundService {
  _FakeBackgroundService()
      : super(
          notificationService: _FakeNotificationService(),
          locationService: _FakeLocationService(),
        );
  @override
  Future<void> initialize() async {}
  @override
  void updateSettings(settings) {}
  @override
  Future<void> onDrivingStarted(TripLeg leg) async {}
  @override
  Future<void> onDrivingStopped() async {}
  @override
  Future<void> onStillDrivingPressed() async {}
  @override
  void dispose() {}
}

class _FakeSheetsService extends SheetsService {
  @override
  Future<bool> get isSignedIn async => false;
  @override
  Future<void> signIn() async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<int> appendLegs(
    List<TripLeg> legs, {
    required String sheetId,
    required String sheetTab,
    List<int>? deletedLegIds,
    Future<void> Function(int legId)? onSynced,
  }) async =>
      0;
}

class _FakeOdometerVisionService extends OdometerVisionService {
  @override
  Future<int?> extractOdometer(String imagePath, {int? expectedHint}) async =>
      null;
}

// ─── Helpers ───────────────────────────────────────────────────────────────

Future<void> resetDatabase() async {
  final db = await DatabaseService.database;
  await db.delete('trip_legs');
  await db.delete('routes');
  await db.delete('settings');
  await db.delete('deleted_leg_ids');
}

/// Fixed pumps without settling — for asserting transient UI (SnackBars)
/// that pumpAndSettle would otherwise wait out and dismiss.
Future<void> pumpFor(WidgetTester tester, [int ms = 800]) async {
  final steps = (ms / 100).ceil();
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// pumpAndSettle that won't hang forever on a transient progress spinner.
Future<void> settle(WidgetTester tester, [int timeoutMs = 6000]) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      Duration(milliseconds: timeoutMs),
    );
  } catch (_) {
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }
}

Future<void> pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificationServiceProvider
            .overrideWithValue(_FakeNotificationService()),
        locationServiceProvider.overrideWithValue(_FakeLocationService()),
        backgroundServiceProvider.overrideWithValue(_FakeBackgroundService()),
        sheetsServiceProvider.overrideWithValue(_FakeSheetsService()),
        odometerVisionServiceProvider
            .overrideWithValue(_FakeOdometerVisionService()),
      ],
      child: const KilometrikorvausApp(),
    ),
  );
  await settle(tester);
  // Let HomeScreen's post-frame seeding/loading complete.
  await settle(tester);
}

/// The odometer field inside showOdometerDialog (label "Matkamittari (km)").
Finder get _odometerField => find.ancestor(
      of: find.text('Matkamittari (km)'),
      matching: find.byType(TextField),
    );

Finder _formField(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(TextFormField),
    );

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.settings));
  await settle(tester);
}

Future<void> openRoutes(WidgetTester tester) async {
  await tester.tap(find.textContaining('Kaikki reitit'));
  await settle(tester);
}

Future<void> openHistory(WidgetTester tester) async {
  await tester.tap(find.text('Historia').last);
  await settle(tester);
}

/// Tap the AppBar back button (tester.pageBack can't locate it reliably here).
Future<void> goBack(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await settle(tester);
}

/// Scroll [f] into view inside the first Scrollable (settings list is lazy,
/// so off-screen widgets aren't built until scrolled to).
Future<void> scrollIntoView(WidgetTester tester, Finder f) async {
  final sc = find.byType(Scrollable);
  if (sc.evaluate().isEmpty) return;
  await tester.scrollUntilVisible(f, 120, scrollable: sc.first, maxScrolls: 60);
}

/// Scroll to and tap the Settings "Tallenna" (save) button.
Future<void> saveSettings(WidgetTester tester) async {
  await scrollIntoView(tester, find.text('Tallenna'));
  await tester.tap(find.widgetWithText(FilledButton, 'Tallenna'));
}

/// Drive a route to start a trip: opens Routes, taps the named route's tile,
/// fills the odometer, confirms. Leaves the app on Home with an active trip.
Future<void> startTrip(
  WidgetTester tester,
  String routeName,
  int odometer, {
  String purpose = 'Testi',
}) async {
  await openRoutes(tester);
  await tester.tap(find.ancestor(
    of: find.text(routeName),
    matching: find.byType(ListTile),
  ));
  await settle(tester);
  // "Aloita ajo" is both the dialog title and the action button.
  expect(find.text('Aloita ajo'), findsWidgets);
  await tester.enterText(
    find.ancestor(of: find.text('Tarkoitus'), matching: find.byType(TextField)),
    purpose,
  );
  await tester.enterText(_odometerField, '$odometer');
  await tester.tap(find.widgetWithText(FilledButton, 'Aloita ajo'));
  await settle(tester);
}

/// Tap "Olen perillä" on the active-trip card and confirm arrival odometer.
Future<void> arrive(WidgetTester tester, int odometer) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Olen perillä'));
  await settle(tester);
  // Arrival dialog has no purpose field, so exactly one TextField.
  await tester.enterText(find.byType(TextField).last, '$odometer');
  await tester.tap(find.widgetWithText(FilledButton, 'Lopeta ajo'));
  await settle(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetDatabase);

  group('App boot & navigation', () {
    testWidgets('home screen renders', (t) async {
      await pumpApp(t);
      expect(find.text('Ajopäiväkirja'), findsOneWidget);
      expect(find.text('Viimeisimmät reitit'), findsOneWidget);
    });

    testWidgets('navigates to Settings and back', (t) async {
      await pumpApp(t);
      await openSettings(t);
      expect(find.text('Asetukset'), findsOneWidget);
      await goBack(t);
      expect(find.text('Ajopäiväkirja'), findsOneWidget);
    });

    testWidgets('navigates to Routes and back', (t) async {
      await pumpApp(t);
      await openRoutes(t);
      expect(find.text('Reitit'), findsOneWidget);
      await goBack(t);
      expect(find.text('Ajopäiväkirja'), findsOneWidget);
    });

    testWidgets('navigates to History and back', (t) async {
      await pumpApp(t);
      await openHistory(t);
      expect(find.text('Historia'), findsWidgets);
      await goBack(t);
      expect(find.text('Ajopäiväkirja'), findsOneWidget);
    });

    testWidgets('history is empty before any trips', (t) async {
      await pumpApp(t);
      await openHistory(t);
      expect(find.text('Ei ajohistoriaa'), findsOneWidget);
    });
  });

  group('Seeded routes', () {
    testWidgets('two debug routes are seeded', (t) async {
      await pumpApp(t);
      expect(find.text('Töihin'), findsWidgets);
      expect(find.text('Kotiin'), findsWidgets);
    });

    testWidgets('"Kaikki reitit (2)" button present', (t) async {
      await pumpApp(t);
      expect(find.textContaining('Kaikki reitit (2)'), findsOneWidget);
    });

    testWidgets('recent routes show distance', (t) async {
      await pumpApp(t);
      expect(find.textContaining('54.0 km'), findsWidgets);
    });

    testWidgets('route list shows both routes', (t) async {
      await pumpApp(t);
      await openRoutes(t);
      expect(find.text('Töihin'), findsOneWidget);
      expect(find.text('Kotiin'), findsOneWidget);
    });
  });

  group('Route management', () {
    testWidgets('add a new route', (t) async {
      await pumpApp(t);
      await openRoutes(t);
      await tester0Tap(t, 'Lisää uusi reitti');
      await settle(t);
      expect(find.text('Uusi reitti'), findsOneWidget);
      await t.enterText(
          find.ancestor(of: find.text('Nimi'), matching: find.byType(TextField)),
          'Asiakaskäynti');
      await t.enterText(
          find.ancestor(
              of: find.text('Lähtöpaikka'), matching: find.byType(TextField)),
          'Koti');
      await t.enterText(
          find.ancestor(
              of: find.text('Määränpää'), matching: find.byType(TextField)),
          'Asiakas');
      await t.enterText(
          find.ancestor(
              of: find.text('Matkan pituus (km)'),
              matching: find.byType(TextField)),
          '32');
      await t.tap(find.widgetWithText(FilledButton, 'Tallenna'));
      await settle(t);
      expect(find.text('Asiakaskäynti'), findsOneWidget);
    });

    testWidgets('empty route form blocks save', (t) async {
      await pumpApp(t);
      await openRoutes(t);
      await tester0Tap(t, 'Lisää uusi reitti');
      await settle(t);
      await t.tap(find.widgetWithText(FilledButton, 'Tallenna'));
      await settle(t);
      // Dialog stays open (validation prevented pop).
      expect(find.text('Uusi reitti'), findsOneWidget);
    });

    testWidgets('cancel route dialog', (t) async {
      await pumpApp(t);
      await openRoutes(t);
      await tester0Tap(t, 'Lisää uusi reitti');
      await settle(t);
      await t.tap(find.widgetWithText(TextButton, 'Peruuta'));
      await settle(t);
      expect(find.text('Uusi reitti'), findsNothing);
    });

    testWidgets('edit a route via swipe-right', (t) async {
      await pumpApp(t);
      await openRoutes(t);
      await t.drag(find.text('Töihin'), const Offset(500, 0));
      await settle(t);
      expect(find.text('Muokkaa reittiä'), findsOneWidget);
      final nameField =
          find.ancestor(of: find.text('Nimi'), matching: find.byType(TextField));
      await t.enterText(nameField, 'Töihin muokattu');
      await t.tap(find.widgetWithText(FilledButton, 'Tallenna'));
      await settle(t);
      expect(find.text('Töihin muokattu'), findsOneWidget);
    });

    testWidgets('delete a route via swipe-left + confirm', (t) async {
      await pumpApp(t);
      await openRoutes(t);
      await t.drag(find.text('Kotiin'), const Offset(-500, 0));
      await settle(t);
      expect(find.text('Poista reitti'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Poista'));
      await settle(t);
      expect(find.text('Kotiin'), findsNothing);
    });

    testWidgets('cancel route deletion keeps the route', (t) async {
      await pumpApp(t);
      await openRoutes(t);
      await t.drag(find.text('Kotiin'), const Offset(-500, 0));
      await settle(t);
      await t.tap(find.widgetWithText(TextButton, 'Peruuta'));
      await settle(t);
      expect(find.text('Kotiin'), findsOneWidget);
    });

    testWidgets('new route appears on home recent list', (t) async {
      await pumpApp(t);
      await openRoutes(t);
      await tester0Tap(t, 'Lisää uusi reitti');
      await settle(t);
      await t.enterText(
          find.ancestor(of: find.text('Nimi'), matching: find.byType(TextField)),
          'Varikko');
      await t.enterText(
          find.ancestor(
              of: find.text('Lähtöpaikka'), matching: find.byType(TextField)),
          'Koti');
      await t.enterText(
          find.ancestor(
              of: find.text('Määränpää'), matching: find.byType(TextField)),
          'Varikko');
      await t.enterText(
          find.ancestor(
              of: find.text('Matkan pituus (km)'),
              matching: find.byType(TextField)),
          '12');
      await t.tap(find.widgetWithText(FilledButton, 'Tallenna'));
      await settle(t);
      await goBack(t);
      expect(find.text('Varikko'), findsWidgets);
    });
  });

  group('Settings', () {
    testWidgets('shows default values', (t) async {
      await pumpApp(t);
      await openSettings(t);
      expect(find.text('Asetukset'), findsOneWidget);
      expect(find.text('Kirjaudu Googleen'), findsOneWidget);
    });

    testWidgets('saving shows confirmation snackbar', (t) async {
      await pumpApp(t);
      await openSettings(t);
      await t.enterText(_formField('Kotiosoite'), 'Kotikatu 1');
      await saveSettings(t);
      await pumpFor(t, 1000); // SnackBar is transient; don't settle it away
      expect(find.text('Asetukset tallennettu'), findsOneWidget);
    });

    testWidgets('home location persists across reopen', (t) async {
      await pumpApp(t);
      await openSettings(t);
      await t.enterText(_formField('Kotiosoite'), 'Saunatie 9');
      await saveSettings(t);
      await settle(t);
      // _save pops back to Home.
      await openSettings(t);
      expect(find.text('Saunatie 9'), findsOneWidget);
    });

    testWidgets('km rate persists across reopen', (t) async {
      await pumpApp(t);
      await openSettings(t);
      await t.enterText(_formField('Km-korvaus (€/km)'), '0,62');
      await saveSettings(t);
      await settle(t);
      await openSettings(t);
      expect(find.textContaining('0.62'), findsWidgets);
    });

    testWidgets('driver name persists across reopen', (t) async {
      await pumpApp(t);
      await openSettings(t);
      await t.enterText(_formField('Kuljettajan nimi'), 'Matti M');
      await saveSettings(t);
      await settle(t);
      await openSettings(t);
      expect(find.text('Matti M'), findsOneWidget);
    });

    testWidgets('debug logging toggle reveals log actions', (t) async {
      await pumpApp(t);
      await openSettings(t);
      await scrollIntoView(t, find.text('Virheloki'));
      await t.tap(find.text('Virheloki'));
      await settle(t);
      await scrollIntoView(t, find.text('Jaa loki'));
      expect(find.text('Jaa loki'), findsOneWidget);
    });

    testWidgets('sheet tab field is editable', (t) async {
      await pumpApp(t);
      await openSettings(t);
      await t.enterText(_formField('Välilehden nimi'), 'Matkat2026');
      await saveSettings(t);
      await settle(t);
      await openSettings(t);
      expect(find.text('Matkat2026'), findsOneWidget);
    });
  });

  group('Driving flow', () {
    testWidgets('start dialog appears from route', (t) async {
      await pumpApp(t);
      await openRoutes(t);
      await t.tap(find.ancestor(
          of: find.text('Töihin'), matching: find.byType(ListTile)));
      await settle(t);
      expect(find.textContaining('Reitti:'), findsOneWidget);
    });

    testWidgets('empty odometer blocks start', (t) async {
      await pumpApp(t);
      await openRoutes(t);
      await t.tap(find.ancestor(
          of: find.text('Töihin'), matching: find.byType(ListTile)));
      await settle(t);
      await t.tap(find.widgetWithText(FilledButton, 'Aloita ajo'));
      await settle(t);
      expect(find.text('Syötä mittarilukema'), findsOneWidget);
    });

    testWidgets('start trip shows active-trip card', (t) async {
      await pumpApp(t);
      await startTrip(t, 'Töihin', 1000);
      expect(find.text('Ajo käynnissä'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Olen perillä'), findsOneWidget);
    });

    testWidgets('route cards disabled while driving', (t) async {
      await pumpApp(t);
      await startTrip(t, 'Töihin', 1000);
      final aloita = find.widgetWithText(FilledButton, 'Aloita');
      expect(
        tester0Enabled(t, aloita),
        isFalse,
      );
    });

    testWidgets('stop trip clears active card', (t) async {
      await pumpApp(t);
      await startTrip(t, 'Töihin', 1000);
      await arrive(t, 1054);
      expect(find.text('Ajo käynnissä'), findsNothing);
    });

    testWidgets('completed trip shows in today summary', (t) async {
      await pumpApp(t);
      await startTrip(t, 'Töihin', 1000);
      await arrive(t, 1054);
      expect(find.textContaining('Tänään'), findsOneWidget);
      expect(find.textContaining('54.0 km'), findsWidgets);
    });

    testWidgets('km allowance reflected in grand total', (t) async {
      await pumpApp(t);
      await startTrip(t, 'Töihin', 1000);
      await arrive(t, 1100); // 100 km * 0.57 = 57.00
      expect(find.textContaining('€57.00'), findsWidgets);
    });

    testWidgets('return-home trip triggers daily allowance', (t) async {
      await pumpApp(t);
      // Leg 1: Koti→Työ 09:00-ish (now). Leg 2: Työ→Koti (return home).
      await startTrip(t, 'Töihin', 1000);
      await arrive(t, 1054);
      await startTrip(t, 'Kotiin', 1054);
      await arrive(t, 1108);
      // Return home finalizes the day; total km = 108.
      expect(find.textContaining('108.0 km'), findsWidgets);
    });
  });

  group('History', () {
    testWidgets('completed trip appears in history', (t) async {
      await pumpApp(t);
      await startTrip(t, 'Töihin', 1000);
      await arrive(t, 1054);
      await openHistory(t);
      expect(find.text('Töihin'), findsWidgets);
      expect(find.text('Ei ajohistoriaa'), findsNothing);
    });

    testWidgets('edit-leg dialog opens from history', (t) async {
      await pumpApp(t);
      await startTrip(t, 'Töihin', 1000);
      await arrive(t, 1054);
      await openHistory(t);
      await t.tap(find.byType(ListTile).first);
      await settle(t);
      expect(find.text('Muokkaa merkintää'), findsOneWidget);
    });

    testWidgets('edit a leg purpose and save', (t) async {
      await pumpApp(t);
      await startTrip(t, 'Töihin', 1000);
      await arrive(t, 1054);
      await openHistory(t);
      await t.tap(find.byType(ListTile).first);
      await settle(t);
      await t.enterText(
          find.ancestor(
              of: find.text('Tarkoitus'), matching: find.byType(TextField)),
          'Päivitetty syy');
      await t.tap(find.widgetWithText(FilledButton, 'Tallenna'));
      await settle(t);
      expect(find.text('Muokkaa merkintää'), findsNothing);
    });

    testWidgets('delete a leg via swipe', (t) async {
      await pumpApp(t);
      await startTrip(t, 'Töihin', 1000);
      await arrive(t, 1054);
      await openHistory(t);
      await t.drag(find.byType(ListTile).first, const Offset(-500, 0));
      await settle(t);
      expect(find.text('Poista merkintä'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Poista'));
      await settle(t);
      expect(find.text('Ei ajohistoriaa'), findsOneWidget);
    });

    testWidgets('cancel leg deletion keeps the leg', (t) async {
      await pumpApp(t);
      await startTrip(t, 'Töihin', 1000);
      await arrive(t, 1054);
      await openHistory(t);
      await t.drag(find.byType(ListTile).first, const Offset(-500, 0));
      await settle(t);
      await t.tap(find.widgetWithText(TextButton, 'Peruuta'));
      await settle(t);
      expect(find.text('Töihin'), findsWidgets);
    });

    testWidgets('history shows per-day total', (t) async {
      await pumpApp(t);
      await startTrip(t, 'Töihin', 1000);
      await arrive(t, 1100);
      await openHistory(t);
      expect(find.textContaining('100.0 km'), findsWidgets);
    });

    testWidgets('sync without sheet id shows notice', (t) async {
      await pumpApp(t);
      await startTrip(t, 'Töihin', 1000);
      await arrive(t, 1054);
      await openHistory(t);
      await t.tap(find.byIcon(Icons.cloud_upload));
      await pumpFor(t, 800); // SnackBar is transient; don't settle it away
      expect(find.text('Sheets-tunnusta ei ole määritetty'), findsOneWidget);
    });
  });

  group('Calculations end-to-end', () {
    testWidgets('zero-distance trip yields zero allowance', (t) async {
      await pumpApp(t);
      await startTrip(t, 'Töihin', 2000);
      await arrive(t, 2000);
      await openHistory(t);
      expect(find.textContaining('0.0 km'), findsWidgets);
    });

    testWidgets('two legs accumulate total km', (t) async {
      await pumpApp(t);
      await startTrip(t, 'Töihin', 1000);
      await arrive(t, 1040);
      await startTrip(t, 'Kotiin', 1040);
      await arrive(t, 1075); // 40 + 35 = 75 km
      expect(find.textContaining('75.0 km'), findsWidgets);
    });

    testWidgets('grand total combines km allowance', (t) async {
      await pumpApp(t);
      await startTrip(t, 'Töihin', 1000);
      await arrive(t, 1200); // 200 km * 0.57 = 114.00
      expect(find.textContaining('€114.00'), findsWidgets);
    });
  });
}

// ─── tiny finder utilities ─────────────────────────────────────────────────

Future<void> tester0Tap(WidgetTester t, String text) async {
  await t.tap(find.text(text));
}

bool tester0Enabled(WidgetTester t, Finder buttonFinder) {
  final widgets = t.widgetList(buttonFinder);
  for (final w in widgets) {
    if (w is ButtonStyleButton && w.onPressed != null) return true;
  }
  return false;
}
