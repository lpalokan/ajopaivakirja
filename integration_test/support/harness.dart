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
  final count = sc.evaluate().length;
  if (count == 0) return;
  // Neither `.first` nor `.last` is reliable: the tree holds many
  // Scrollables that are not the one we want — every EditableText wraps
  // one (single-line, often horizontal / maxScrollExtent == 0), and a
  // pushed route leaves the previous screen's scrollables (e.g. the
  // horizontal RouteChipRow, or Home's lists behind a dialog/route) in
  // the tree. Probe each vertical, scrollable candidate, but RESTORE its
  // offset if it didn't reveal the target — otherwise an over-eager probe
  // leaves unrelated lists (e.g. the Settings ListView) scrolled away and
  // breaks later steps in the same scenario.
  for (var i = 0; i < count; i++) {
    final candidate = sc.at(i);
    ScrollPosition pos;
    try {
      pos = tester.state<ScrollableState>(candidate).position;
    } catch (_) {
      continue;
    }
    if (pos.axis != Axis.vertical) continue;
    if (pos.maxScrollExtent <= 0.0) continue;
    final original = pos.pixels;
    try {
      await tester.scrollUntilVisible(
        f,
        300,
        scrollable: candidate,
        maxScrolls: 15,
      );
    } catch (_) {}
    if (f.evaluate().isNotEmpty) return;
    // Wrong scrollable — undo the probe so we don't displace it for
    // subsequent finders.
    try {
      tester.state<ScrollableState>(candidate).position.jumpTo(original);
      await tester.pump();
    } catch (_) {}
  }
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
  final link = find.textContaining('Kaikki reitit');
  if (link.evaluate().isEmpty) await scrollIntoView(tester, link);
  if (link.evaluate().isNotEmpty) {
    await tester.ensureVisible(link.first);
    await settle(tester);
  }
  await tester.tap(link.first);
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
  // Ensure the field is fully visible and focused so enterText cannot
  // route through whatever EditableText currently owns the input
  // connection (e.g. a previously-focused field higher up).
  await tester.ensureVisible(f.first);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(f.first);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.enterText(f, value);
  await tester.pump(const Duration(milliseconds: 200));
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
  // until the button is actually in the tree. Pick the first vertical,
  // scrollable candidate — `sc.first` could land on a text-field's
  // internal Scrollable (horizontal / maxScrollExtent==0).
  final btn = find.widgetWithText(FilledButton, 'Tallenna');
  for (var i = 0; i < 12 && btn.evaluate().isEmpty; i++) {
    final scrollables = find.byType(Scrollable);
    final count = scrollables.evaluate().length;
    for (var j = 0; j < count; j++) {
      try {
        final pos = tester.state<ScrollableState>(scrollables.at(j)).position;
        if (pos.axis != Axis.vertical) continue;
        if (pos.maxScrollExtent <= 0.0) continue;
        pos.jumpTo(pos.maxScrollExtent);
        break;
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
  // Tap the chip to open the override dialog and set the start location.
  //
  // This step MUST set the location: if it silently no-ops, the trip
  // starts from AppSettings.homeLocation ('Koti') and the saved ad-hoc
  // route becomes 'Koti -> ...' instead of '<from> -> ...', which only
  // surfaces much later as a confusing "0 widgets" on the routes page.
  // So every stage asserts, failing loudly at the real point of breakage.
  final chip = find.byType(InputChip);
  await scrollIntoView(tester, chip);
  await waitFor(tester, chip);
  await tester.ensureVisible(chip.first);
  await tester.tap(chip.first);
  await settle(tester);

  // Confirm the override dialog actually opened.
  await waitFor(tester, find.text('Muuta sijainti'));
  expect(
    find.text('Muuta sijainti'),
    findsOneWidget,
    reason: 'LocationChip override dialog did not open after tapping the '
        'chip; the ad-hoc start location would silently fall back to '
        "AppSettings.homeLocation ('Koti').",
  );

  // Target the dialog's autocomplete field directly: there is exactly one
  // TextField inside the 'Muuta sijainti' AlertDialog. Going via the
  // 'Sijainti' label finder is fragile — InputDecorator renders the label
  // as multiple Text widgets during the floating-label animation, and the
  // StartCard's odometer field is also in the tree behind the modal.
  final locField = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(TextField),
  );
  // Tap first to force focus onto the dialog field — without it, focus
  // can stay on the StartCard's auto-focused odometer field and enterText
  // routes through the wrong EditableText connection.
  await tester.tap(locField.first);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.enterText(locField.first, from);
  await tester.pump(const Duration(milliseconds: 300));
  // Dismiss the Autocomplete overlay and soft keyboard so the dialog
  // action buttons are not shifted behind the scrim.
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump(const Duration(milliseconds: 300));

  // Self-diagnosing checkpoint: confirm the text actually landed in the
  // dialog field before we commit it. If this fails, the bug is in text
  // entry / the autocomplete field; if this passes but the chip check
  // below fails, the bug is in propagation back to the chip.
  final dialogText = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.text(from),
  );
  expect(
    dialogText,
    findsWidgets,
    reason: "Typed start location '$from' did not land in the 'Muuta "
        "sijainti' dialog field — text entry / finder is the problem, "
        'not propagation.',
  );

  final useBtn = find.widgetWithText(FilledButton, 'Käytä');
  await tester.tap(useBtn.first);
  await settle(tester);

  // The chip now renders the chosen label; if it doesn't, the location
  // never propagated and the rest of the scenario would silently run
  // from 'Koti'. Fail here instead.
  await waitFor(tester, find.text(from));
  expect(
    find.text(from),
    findsWidgets,
    reason: "Start location '$from' was not applied to the LocationChip; "
        "the ad-hoc trip would start from 'Koti' and the saved route "
        "would be 'Koti -> ...' instead of '$from -> ...'.",
  );

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

Future<void> longPressLiveCounter(WidgetTester tester) async {
  // The active-trip card renders the live km counter as "<x.x> km" inside
  // a Semantics-wrapped widget. Long-press triggers the WCAG 2.2.2 freeze
  // affordance — counter and pulse pause, "Pinjattu" badge appears.
  await waitFor(tester, find.textContaining(RegExp(r'^\d+\.\d km$')));
  final counter = find.byKey(const ValueKey('active-trip-counter'));
  if (counter.evaluate().isNotEmpty) {
    await tester.longPress(counter.first);
  } else {
    await tester.longPress(
      find.textContaining(RegExp(r'^\d+\.\d km$')).first,
    );
  }
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
  // The AppBar sync button and the StatusChipRow's "unsynced" chip both
  // use Symbols.cloud_upload, so find.byIcon is ambiguous. Target the
  // AppBar button via its unique tooltip.
  await tester.tap(find.byTooltip('Synkronoi Sheetsiin'));
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
