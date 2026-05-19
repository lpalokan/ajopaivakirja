// Reusable engine for the Gherkin (bdd_widget_test) integration suite.
//
// Step definitions in integration_test/features/step/ are thin wrappers that
// delegate here. Keep all real test logic in this file so scenarios stay
// declarative and steps stay one-liners.
//
// The real app is pumped (KilometrikorvausApp) against the real on-device
// SQLite DB (wiped per scenario). Only external-world services
// (notifications/location/background/Sheets/OCR) are replaced with no-op
// Riverpod overrides, so no native dialogs or network are hit. In debug
// builds HomeScreen seeds two routes ("Töihin" Koti→Työ 54 km, "Kotiin"
// Työ→Koti 54 km), so every scenario starts from that deterministic state.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

import 'package:kilometrikorvaus/main.dart';
import 'package:kilometrikorvaus/models/trip_leg.dart';
import 'package:kilometrikorvaus/services/background_service.dart';
import 'package:kilometrikorvaus/services/database_service.dart';
import 'package:kilometrikorvaus/services/file_opener_service.dart';
import 'package:kilometrikorvaus/services/location_service.dart';
import 'package:kilometrikorvaus/services/notification_service.dart';
import 'package:kilometrikorvaus/services/odometer_vision_service.dart';
import 'package:kilometrikorvaus/services/sheets_service.dart';

// ─── Fakes ─────────────────────────────────────────────────────────────────

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
  Future<bool> hasPermissionGranted() async => false;
  @override
  Future<void> startMonitoringDestination(
    String d,
    settings,
    NotificationService n,
  ) async {}
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
  }) async => 0;
}

class _FakeOdometerVisionService extends OdometerVisionService {
  @override
  Future<OdometerVisionResult?> extractOdometer(
    String imagePath, {
    int? expectedHint,
  }) async => null;
}

/// Records the "open in external app" call instead of firing a native
/// ACTION_VIEW intent (which would leave the test on an app chooser).
class _FakeFileOpenerService extends FileOpenerService {
  String? openedPath;
  @override
  Future<String?> open(String path) async {
    openedPath = path;
    return null;
  }
}

final _fakeFileOpener = _FakeFileOpenerService();

// ─── Low-level helpers ─────────────────────────────────────────────────────

Future<void> resetDatabase() async {
  final db = await DatabaseService.database;
  await db.delete('expenses');
  await db.delete('trip_legs');
  await db.delete('routes');
  await db.delete('settings');
  await db.delete('deleted_leg_ids');
}

/// Fixed pumps without settling — for transient UI (SnackBars) that
/// pumpAndSettle would otherwise wait out and dismiss.
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

/// Pump until [f] matches at least one widget (or [timeoutMs] elapses).
Future<void> waitFor(
  WidgetTester tester,
  Finder f, {
  int timeoutMs = 10000,
}) async {
  final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (f.evaluate().isNotEmpty) return;
  }
}

/// Scroll [f] into view inside the first Scrollable (lazy lists don't build
/// off-screen widgets). Swallows not-found so the caller's expect reports it.
Future<void> scrollIntoView(WidgetTester tester, Finder f) async {
  if (f.evaluate().isNotEmpty) return; // already present, don't scroll
  final sc = find.byType(Scrollable);
  if (sc.evaluate().isEmpty) return;
  // If the list already fits the screen there is nothing to scroll —
  // calling scrollUntilVisible here just overscroll-bounces repeatedly
  // (looks like the screen "vibrating"). Skip it.
  try {
    final pos = tester.state<ScrollableState>(sc.first).position;
    if (pos.maxScrollExtent <= 0.0) return;
  } catch (_) {
    return;
  }
  try {
    await tester.scrollUntilVisible(
      f,
      300,
      scrollable: sc.first,
      maxScrolls: 15,
    );
  } catch (_) {}
}

Finder get _odometerField => find.ancestor(
  of: find.text('Matkamittari (km)'),
  matching: find.byType(TextField),
);

Finder get _arrivalOdoField => find.ancestor(
  of: find.text('Matkamittari perillä (km)'),
  matching: find.byType(TextField),
);

Finder _formField(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(TextFormField));

Finder _dialogField(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(TextField));

// ─── Step-level actions (called from step definitions) ─────────────────────

Future<void> launchApp(WidgetTester tester) async {
  _fakeFileOpener.openedPath = null;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificationServiceProvider.overrideWithValue(
          _FakeNotificationService(),
        ),
        locationServiceProvider.overrideWithValue(_FakeLocationService()),
        backgroundServiceProvider.overrideWithValue(_FakeBackgroundService()),
        sheetsServiceProvider.overrideWithValue(_FakeSheetsService()),
        odometerVisionServiceProvider.overrideWithValue(
          _FakeOdometerVisionService(),
        ),
        fileOpenerServiceProvider.overrideWithValue(_fakeFileOpener),
      ],
      child: const KilometrikorvausApp(),
    ),
  );
  await settle(tester);
  // Wait for the 2nd seeded route so post-frame seeding finishes before the
  // scenario proceeds (and before teardown — else RouteNotifier-after-dispose).
  await waitFor(tester, find.text('Kotiin'));
  await settle(tester);
}

Future<void> openSettings(WidgetTester tester) async {
  await waitFor(tester, find.byIcon(Symbols.settings));
  await tester.tap(find.byIcon(Symbols.settings));
  await settle(tester);
}

Future<void> openRoutes(WidgetTester tester) async {
  await tester.tap(find.textContaining('Kaikki reitit'));
  await settle(tester);
}

Future<void> openHistory(WidgetTester tester) async {
  await tester.tap(find.byIcon(Symbols.history));
  await settle(tester);
}

Future<void> goBack(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await settle(tester);
}

Future<void> expectVisible(WidgetTester tester, String text) async {
  final f = find.text(text);
  // Poll first (no scroll) so a transient/animating frame doesn't trigger
  // a destructive scroll away from an already-present (e.g. top) widget.
  await waitFor(tester, f, timeoutMs: 6000);
  if (f.evaluate().isEmpty) await scrollIntoView(tester, f);
  expect(f, findsWidgets);
}

Future<void> expectAbsent(WidgetTester tester, String text) async {
  expect(find.text(text), findsNothing);
}

/// Assert a persisted settings value in the on-device SQLite DB. More
/// reliable than re-reading a rebuilt, lazily-laid-out Settings screen.
Future<void> expectSetting(
  WidgetTester tester,
  String key,
  String value,
) async {
  String? actual;
  final deadline = DateTime.now().add(const Duration(seconds: 4));
  while (DateTime.now().isBefore(deadline)) {
    actual = await DatabaseService.getSetting(key);
    if (actual == value) return;
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(actual, value);
}

Future<void> expectContains(WidgetTester tester, String text) async {
  final f = find.textContaining(text);
  await waitFor(tester, f, timeoutMs: 6000);
  if (f.evaluate().isEmpty) await scrollIntoView(tester, f);
  expect(f, findsWidgets);
}

Future<void> tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  if (f.evaluate().isEmpty) await scrollIntoView(tester, f);
  await tester.tap(f.first);
  await settle(tester);
}

Future<void> enterSettingsField(
  WidgetTester tester,
  String value,
  String label,
) async {
  final f = _formField(label);
  if (f.evaluate().isEmpty) await scrollIntoView(tester, f);
  await tester.enterText(f, value);
}

Future<void> enterDialogField(
  WidgetTester tester,
  String value,
  String label,
) async {
  await tester.enterText(_dialogField(label), value);
}

Future<void> saveSettings(WidgetTester tester) async {
  // Close the soft keyboard (it shrinks the list and fights scrolling).
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 300));

  // The Save button is the last child of a lazy ListView, so its
  // maxScrollExtent grows as more rows build. A single jumpTo can land
  // short and never build the button — re-jump to the (growing) bottom
  // until the button is actually in the tree.
  final btn = find.widgetWithText(FilledButton, 'Tallenna');
  for (var i = 0; i < 12 && btn.evaluate().isEmpty; i++) {
    final sc = find.byType(Scrollable);
    if (sc.evaluate().isNotEmpty) {
      try {
        final pos = tester.state<ScrollableState>(sc.first).position;
        pos.jumpTo(pos.maxScrollExtent);
      } catch (_) {}
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  await settle(tester);
  if (btn.evaluate().isEmpty) return;
  await tester.ensureVisible(btn.first);
  await settle(tester);
  await tester.tap(btn.first, warnIfMissed: false);
  await pumpFor(tester, 1000); // keep the transient SnackBar visible
}

Future<void> startTrip(WidgetTester tester, String route, int odometer) async {
  // Tap the route chip on the home screen to select it as a shortcut.
  // The chip is inside a RouteChip widget in the RouteChipRow.
  await waitFor(tester, find.text(route));
  await tester.tap(find.text(route).first);
  await settle(tester);
  // The StartCard now shows "Reitti: $route" — verify it took effect.
  await waitFor(tester, find.textContaining('Reitti:'));

  // Enter odometer in the StartCard field (on home, not in a dialog).
  await tester.enterText(_odometerField, '$odometer');

  // Tap "Aloita ajo" on the StartCard (bottom of home screen).
  final startBtn = find.widgetWithText(FilledButton, 'Aloita ajo');
  await scrollIntoView(tester, startBtn);
  await tester.tap(startBtn.first);
  await settle(tester);
  await waitFor(tester, find.widgetWithText(FilledButton, 'Olen perillä'));
}

Future<void> startAdHoc(WidgetTester tester, String from, int odometer) async {
  // The LocationChip auto-resolves GPS; in the test suite the fake
  // LocationService returns no permission, so the chip shows a fallback.
  // Tap the chip to open the autocomplete dialog and manually enter the
  // start location, matching the pre-redesign workflow.
  final chip = find.byType(InputChip);
  if (chip.evaluate().isNotEmpty) {
    await tester.tap(chip.first);
    await settle(tester);
    // The autocomplete dialog should now be visible.
    final autoField = find.byType(TextField);
    if (autoField.evaluate().isNotEmpty) {
      await tester.enterText(autoField.last, from);
      await tester.pump(const Duration(milliseconds: 300));
    }
    // Dismiss the Autocomplete overlay and soft keyboard so the
    // dialog action buttons are not shifted behind the scrim.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 300));
    final useBtn = find.widgetWithText(FilledButton, 'Käytä');
    if (useBtn.evaluate().isNotEmpty) {
      await tester.tap(useBtn.first);
      await settle(tester);
    }
  }

  await tester.enterText(_odometerField, '$odometer');
  final startBtn = find.widgetWithText(FilledButton, 'Aloita ajo');
  await scrollIntoView(tester, startBtn);
  await tester.tap(startBtn.first);
  await settle(tester);
  await waitFor(tester, find.widgetWithText(FilledButton, 'Olen perillä'));
}

Future<void> arriveAdHoc(WidgetTester tester, String to, int odometer) async {
  await settle(tester);
  await waitFor(tester, find.widgetWithText(FilledButton, 'Olen perillä'));
  // The first "Olen perillä" is the in-card CTA (which opens the arrival
  // dialog); the bottom-anchored duplicate is last in tree order.
  await tester.tap(find.widgetWithText(FilledButton, 'Olen perillä').first);
  await settle(tester);
  await waitFor(tester, _dialogField('Määränpää'));
  await tester.enterText(_dialogField('Määränpää'), to);
  await tester.enterText(_arrivalOdoField, '$odometer');
  await waitFor(tester, find.widgetWithText(FilledButton, 'Lopeta ajo'));
  await tester.tap(find.widgetWithText(FilledButton, 'Lopeta ajo').first);
  await settle(tester);
}

Future<void> arrive(WidgetTester tester, int odometer) async {
  // Let the route-screen pop finish so only Home's active card remains
  // (both screens show an "Olen perillä" button mid-transition).
  await settle(tester);
  await waitFor(tester, find.widgetWithText(FilledButton, 'Olen perillä'));
  // Tap the in-card CTA (first in tree) which opens the arrival dialog.
  await tester.tap(find.widgetWithText(FilledButton, 'Olen perillä').first);
  await settle(tester);
  await waitFor(tester, _arrivalOdoField);
  await tester.enterText(_arrivalOdoField, '$odometer');
  await waitFor(tester, find.widgetWithText(FilledButton, 'Lopeta ajo'));
  await tester.tap(find.widgetWithText(FilledButton, 'Lopeta ajo').first);
  await settle(tester);
}

Future<void> addRoute(
  WidgetTester tester,
  String name,
  String from,
  String to,
  int km,
) async {
  await openRoutes(tester);
  await tapText(tester, 'Lisää uusi reitti');
  await waitFor(tester, find.text('Uusi reitti'));
  await tester.enterText(_dialogField('Nimi'), name);
  await tester.enterText(_dialogField('Lähtöpaikka'), from);
  await tester.enterText(_dialogField('Määränpää'), to);
  await tester.enterText(_dialogField('Matkan pituus (km)'), '$km');
  await tester.tap(find.widgetWithText(FilledButton, 'Tallenna'));
  await settle(tester);
}

Future<void> openAddRouteDialog(WidgetTester tester) async {
  await openRoutes(tester);
  await tapText(tester, 'Lisää uusi reitti');
  await waitFor(tester, find.text('Uusi reitti'));
}

Future<void> swipeLeft(WidgetTester tester, String text) async {
  await tester.drag(find.text(text), const Offset(-500, 0));
  await settle(tester);
}

Future<void> swipeRight(WidgetTester tester, String text) async {
  await tester.drag(find.text(text), const Offset(500, 0));
  await settle(tester);
}

Future<void> tapDialogButton(WidgetTester tester, String label) async {
  // find.widgetWithText matches by exact type; ButtonStyleButton is
  // abstract, so match its subtypes (FilledButton/TextButton/…) instead.
  final btn = find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );
  if (btn.evaluate().isNotEmpty) {
    await tester.tap(btn.first);
  } else {
    await tester.tap(find.text(label).first);
  }
  await settle(tester);
}

Future<void> syncToSheets(WidgetTester tester) async {
  await tester.tap(find.byIcon(Symbols.cloud_upload));
  await pumpFor(tester, 800); // transient SnackBar
}

Future<void> exportCsv(WidgetTester tester) async {
  await tester.tap(find.byIcon(Symbols.table_chart));
  await settle(tester);
  await waitFor(tester, find.text('Avaa sovelluksessa'));
}

Future<void> expectFileOpened(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 4));
  while (DateTime.now().isBefore(deadline)) {
    if (_fakeFileOpener.openedPath != null) break;
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(_fakeFileOpener.openedPath, isNotNull);
  expect(_fakeFileOpener.openedPath, endsWith('.csv'));
}

Future<void> toggleDebugLogging(WidgetTester tester) async {
  await scrollIntoView(tester, find.text('Virheloki'));
  await tester.tap(find.text('Virheloki'));
  await settle(tester);
}

// ─── Draft helpers ─────────────────────────────────────────────────────────

/// Insert a draft (incomplete) leg directly into the on-device database.
/// This simulates a trip that was started but never finished (abandoned).
/// Uses [date] (yyyy-MM-dd) so callers can control whether the leg appears
/// on today's timeline or only in history.
Future<TripLeg> createDraftLeg({
  required String startLocation,
  required int startOdometer,
  String? endLocation,
  String? routeDescription,
  String date = '2026-05-18',
}) async {
  final leg = TripLeg(
    date: date,
    legOrder: 1,
    startTime: DateTime(2026, 5, 18, 8, 0),
    startOdometer: startOdometer,
    startLocation: startLocation,
    endLocation: endLocation ?? '',
    endOdometer: null,
    routeDescription: routeDescription,
    driver: 'Testikuljettaja',
  );
  return await DatabaseService.insertTripLeg(leg);
}

// ─── CSV content verification ──────────────────────────────────────────────

/// Read the last exported CSV file and assert it contains no data rows
/// (only the UTF-8 BOM + header line). Used to verify drafts are filtered
/// from exports.
Future<void> expectCsvHasOnlyHeaderRow(WidgetTester tester) async {
  final path = _fakeFileOpener.openedPath;
  expect(path, isNotNull, reason: 'No exported file was opened');
  final content = await File(path!).readAsString();
  // Split by CRLF (RFC 4180), filter out empty trailing lines.
  final lines = content
      .split('\r\n')
      .where((l) => l.trim().isNotEmpty)
      .toList();
  expect(lines.length, 1, reason: 'Expected only header row, got:\n$content');
}
