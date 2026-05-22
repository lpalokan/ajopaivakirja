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

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
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
  // Owns its own broadcast controller so scenarios can synthesise GPS
  // updates without touching real Geolocator. Used by the regression
  // scenario for the kilometer-tracking-predefined-routes bug to prove
  // that nothing in the app subscribes to live position updates anymore.
  final StreamController<Position> _fakeController =
      StreamController<Position>.broadcast();

  @override
  Stream<Position> get positionStream => _fakeController.stream;

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

  void pushFakePosition(Position p) {
    if (!_fakeController.isClosed) _fakeController.add(p);
  }
}

// Single fake instance per launch so scenarios can reach it via
// `simulateGpsMovement` without going through the ProviderContainer.
_FakeLocationService _fakeLocation = _FakeLocationService();

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
  _fakeLocation = _FakeLocationService();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificationServiceProvider.overrideWithValue(
          _FakeNotificationService(),
        ),
        locationServiceProvider.overrideWithValue(_fakeLocation),
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
  // Home AppBar uses Icons.history (not Symbols.history) since the
  // Material Symbols variable-font axis was not rendering the 0xe8b3
  // glyph reliably — see lib/screens/home_screen.dart.
  await tester.tap(find.byIcon(Icons.history));
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
  // When the same label appears in both an interactive widget (chip,
  // button) and a non-interactive one (heading, preview card), `f.first`
  // is whichever comes earlier in tree order — that's not necessarily
  // the tappable one. Prefer a Text descendant of an InkWell so the tap
  // hits the chip/button rather than a label that just happens to
  // display the same string.
  final tappable = find.descendant(
    of: find.byType(InkWell),
    matching: find.text(text),
  );
  final target = tappable.evaluate().isNotEmpty ? tappable.first : f.first;
  await tester.tap(target);
  await settle(tester);
}

Future<void> enterSettingsField(
  WidgetTester tester,
  String value,
  String label,
) async {
  final f = _formField(label);
  if (f.evaluate().isEmpty) await scrollIntoView(tester, f);
  await tester.ensureVisible(f.first);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(f.first);
  await tester.pump(const Duration(milliseconds: 200));

  // Write directly to the TextFormField's controller rather than going
  // through `tester.enterText`. The latter routes through the single test
  // TextInput connection, which races with whatever EditableText was
  // focused first (in Settings, the topmost TextFormField wins the
  // connection on screen open). For deep fields (e.g. Sheet tab, the last
  // TextFormField in the form) the typed value silently lands on the
  // wrong field and the test then sees the default value in the DB.
  // Direct controller writes always reach the intended field; the on-
  // change listeners that matter for our forms (FormField validators,
  // save-button-state listeners) all fire from the controller, so this
  // is observationally equivalent to a real keystroke.
  final tfWidget = tester.widget<TextFormField>(f.first);
  final ctrl = tfWidget.controller;
  if (ctrl != null) {
    ctrl.text = value;
    ctrl.selection = TextSelection.collapsed(offset: value.length);
  } else {
    // No controller on the widget — fall back to enterText so we still
    // type *something* and the failure shows up at the assertion.
    await tester.enterText(f, value);
  }
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
  // The deepest field (Sheet tab, in the Google Sheets card) sits behind
  // several other cards, so reflow after the keyboard closes can move the
  // Tallenna button further than a single pump captures — let things
  // settle before we start hunting for it.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 300));
  await settle(tester);

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
  if (btn.evaluate().isEmpty) {
    // The Tallenna button never materialised in the tree. Don't silently
    // return — that defers the failure to a downstream `expectSetting`
    // assertion seconds later and hides the real cause. Fail here so the
    // test report points at the actual problem.
    fail(
      'saveSettings: "Tallenna" FilledButton never appeared after 12 '
      'jumpTo(maxScrollExtent) attempts. The Settings ListView did not '
      'build down to its last child — either the list is too long for the '
      'scroll budget, or the button moved.',
    );
  }
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
    reason:
        'LocationChip override dialog did not open after tapping the '
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
  //
  // We avoid `tester.enterText` here for one specific reason: it routes
  // through the single test TextInput connection, and on a cold dialog
  // the StartCard's auto-focused odometer field is still the "current"
  // connection while RawAutocomplete is wiring up. Even with tap +
  // pump + retry the typed value occasionally lands on the odometer
  // field instead of ours. Writing directly to the TextEditingController
  // on the TextField widget bypasses that race — RawAutocomplete still
  // sees the change (its optionsBuilder listens to the controller), and
  // the "Käytä" button still reads ctrl.text on press, so the rest of
  // the flow is identical to a real keystroke.
  await tester.tap(locField.first);
  await tester.pump(const Duration(milliseconds: 200));
  final tfWidget = tester.widget<TextField>(locField.first);
  final ctrl = tfWidget.controller;
  expect(
    ctrl,
    isNotNull,
    reason:
        "Muuta sijainti dialog's TextField has no controller — the "
        'LocationAutocomplete API changed and the harness needs updating.',
  );
  ctrl!.text = from;
  ctrl.selection = TextSelection.collapsed(offset: from.length);
  // One sync pump for the controller's notifyListeners → EditableText
  // rebuild, plus a longer pump to let RawAutocomplete settle its
  // options overlay before we tap "Käytä".
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));

  // Verify the controller — NOT find.text — that the write actually
  // stuck. find.text against EditableText was flaking on cold-start
  // first scenarios while the controller itself reliably had the value;
  // the Käytä button reads ctrl.text.trim() on press anyway, so the
  // controller is the source of truth that matters for propagation.
  expect(
    ctrl.text,
    from,
    reason:
        "Direct controller write to 'Muuta sijainti' dialog field "
        "did not stick: expected '$from' but controller has "
        "'${ctrl.text}'. The TextField finder may be matching a stale "
        'or different field.',
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
    reason:
        "Start location '$from' was not applied to the LocationChip; "
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

/// Push two synthetic GPS fixes ~[km] kilometres apart through the fake
/// LocationService's broadcast stream. Used to prove that the active-trip
/// distance is not inflated by GPS deltas (the kilometer-tracking-
/// predefined-routes regression). One degree of latitude is ~111.32 km, so
/// shifting the second fix by `km / 111.32` degrees gives the expected
/// haversine delta.
Future<void> simulateGpsMovement(WidgetTester tester, double km) async {
  final now = DateTime.now();
  Position make(double lat, double lon) => Position(
        latitude: lat,
        longitude: lon,
        timestamp: now,
        accuracy: 5.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );

  _fakeLocation.pushFakePosition(make(60.0, 25.0));
  await tester.pump(const Duration(milliseconds: 50));
  _fakeLocation.pushFakePosition(make(60.0 + km / 111.32, 25.0));
  await tester.pump(const Duration(milliseconds: 50));
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

// ─── Bottom "Olen perillä" button ─────────────────────────────────────────

/// Taps the bottom-anchored "Olen perillä" FilledButton (the second one in
/// tree order during active driving). The in-card CTA comes first; the
/// bottom duplicate is last.
Future<void> tapBottomArriveButton(WidgetTester tester) async {
  await settle(tester);
  await waitFor(tester, find.widgetWithText(FilledButton, 'Olen perillä'));
  final buttons = find.widgetWithText(FilledButton, 'Olen perillä');
  await tester.tap(buttons.last);
  await settle(tester);
}

// ─── StartCard odometer field value verification ───────────────────────────

/// Asserts the StartCard's odometer TextField on the home screen holds
/// [value]. Used after completing a trip to confirm the field pre-fills
/// from the last leg's end odometer.
Future<void> expectOdometerFieldValue(WidgetTester tester, int value) async {
  await waitFor(tester, _odometerField);
  final tf = tester.widget<TextField>(_odometerField);
  expect(tf.controller?.text, value.toString());
}

// ─── Arrival dialog odometer field value verification ──────────────────────

/// Asserts the arrival dialog's odometer TextField holds [value].
/// Used to verify the dialog pre-fills the expected end odometer for
/// route-based trips.
Future<void> expectArrivalOdometerFieldValue(
  WidgetTester tester,
  int value,
) async {
  await waitFor(tester, _arrivalOdoField);
  final tf = tester.widget<TextField>(_arrivalOdoField);
  expect(tf.controller?.text, value.toString());
}
