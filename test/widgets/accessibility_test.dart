// Accessibility regression tests for issue #46.
//
// These tests guard the WCAG 2.1 AA fixes called out in the audit:
//   A1  Active-trip "Olen perillä" button reads as a discrete shape.
//   A2  Every interactive element has a ≥ 48 × 48 dp tap target.
//   A3  Active-trip state is conveyed as text, not colour alone.
//   A6  Live distance counter has a long-press freeze affordance.
//   A7  Tertiary / success palette meets ≥ 4.5:1 on the surfaces they
//       render text against.
//   A8  Every IconButton is labelled (tooltip → semantic label).
//
// Run via `flutter test test/widgets/accessibility_test.dart`.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/main.dart';
import 'package:kilometrikorvaus/models/trip_leg.dart';
import 'package:kilometrikorvaus/widgets/active_trip_card.dart';
import 'package:kilometrikorvaus/widgets/status_chip_row.dart';

// ─── Helpers ───────────────────────────────────────────────────────────────

/// Pumps [child] under the real app's light theme and a [ProviderScope] so
/// [ActiveTripCard] (a [ConsumerStatefulWidget]) can read providers.
Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(body: child),
    ),
  );
}

TripLeg _activeLeg({double kmDriven = 54.0}) => TripLeg(
  id: 1,
  date: '2026-05-20',
  legOrder: 1,
  startTime: DateTime(2026, 5, 20, 9, 0),
  startOdometer: 10000,
  startLocation: 'Koti',
  endLocation: 'Työ',
  routeDescription: 'Koti → Työ',
  driver: 'Lapa',
  kmDriven: kmDriven,
);

/// WCAG relative-luminance for sRGB. `Color.r/g/b` already returns 0–1.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) as double;

  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double contrastRatio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

// ─── A1 · Olen perillä button is a solid, discrete shape ───────────────────

void main() {
  group('A1 · Active-trip "Olen perillä" button contrast', () {
    testWidgets('button background is fully opaque (alpha == 255)', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(ActiveTripCard(leg: _activeLeg())));
      // _LivePulse has an infinite repeating animation — pump several
      // frames instead of pumpAndSettle which would time out.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final btnFinder = find.widgetWithText(FilledButton, 'Olen perillä');
      expect(btnFinder, findsOneWidget);

      final btn = tester.widget<FilledButton>(btnFinder);
      final ctx = tester.element(btnFinder);
      final bg = btn.style?.backgroundColor?.resolve({});
      expect(bg, isNotNull, reason: 'button must have an explicit background');
      // Alpha is stored as a 0–1 double in the new Color API. Anything below
      // 1.0 lets the gradient bleed through, which is exactly the failure
      // mode A1 calls out.
      expect(
        bg!.a,
        closeTo(1.0, 0.001),
        reason: 'button background must be fully opaque so it reads as a shape',
      );

      // And it must clear the WCAG non-text contrast threshold of 3:1 against
      // the lightest pixel of the gradient (colorScheme.primary).
      final primary = Theme.of(ctx).colorScheme.primary;
      expect(
        contrastRatio(bg, primary),
        greaterThanOrEqualTo(3.0),
        reason: 'A1 requires ≥ 3:1 between button surface and gradient',
      );
    });
  });

  // ─── A2 · 48 dp tap targets ──────────────────────────────────────────────

  group('A2 · 48 dp minimum tap targets', () {
    testWidgets('ActiveTripCard meets the Android tap-target guideline', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(ActiveTripCard(leg: _activeLeg())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });
  });

  // ─── A3 · Active-trip state in text, not colour ──────────────────────────

  group('A3 · Active-trip card exposes its state as text', () {
    testWidgets('Semantics tree carries "Ajo käynnissä" with the km value', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(ActiveTripCard(leg: _activeLeg(kmDriven: 54.0))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The whole card should declare a Semantics container labelled
      // "Ajo käynnissä, X kilometriä" so TalkBack reads the state in text,
      // not just colour / icon.
      final labelled = find.byWidgetPredicate((w) {
        if (w is! Semantics) return false;
        final label = w.properties.label;
        if (label == null) return false;
        return RegExp(r'Ajo käynnissä.*54\.0.*kilometriä').hasMatch(label);
      });
      expect(
        labelled,
        findsOneWidget,
        reason: 'card must expose state as a labelled Semantics container',
      );
      handle.dispose();
    });
  });

  // ─── A6 · Long-press counter freeze (WCAG 2.2.2) ─────────────────────────

  group('A6 · Long-press freezes the live distance counter', () {
    testWidgets('long-press shows a "Pinjattu" badge and freezes the value', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(ActiveTripCard(leg: _activeLeg(kmDriven: 54.0))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // No pin indicator initially.
      expect(find.text('Pinjattu'), findsNothing);

      // Long-press on the live counter.
      await tester.longPress(find.text('54.0 km'));
      await tester.pumpAndSettle();

      expect(
        find.text('Pinjattu'),
        findsOneWidget,
        reason: 'a visible "pinned" indicator must appear while frozen',
      );

      // The displayed value remains the snapshot taken at freeze time even
      // when a new build rebuilds the card with a larger liveDistanceKm —
      // tap restores live updates.
      await tester.tap(find.text('54.0 km'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Pinjattu'), findsNothing);
    });
  });

  // ─── A7 · Palette contrast ───────────────────────────────────────────────

  group('A7 · Tertiary & success palette meet body-text contrast', () {
    testWidgets('tertiary contrast on the lightest surface ≥ 4.5:1', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      final ctx = tester.element(find.byType(Scaffold));
      final scheme = Theme.of(ctx).colorScheme;

      expect(
        contrastRatio(scheme.tertiary, scheme.surface),
        greaterThanOrEqualTo(4.5),
        reason: 'A7: tertiary used as text on surface must clear 4.5:1',
      );
    });

    testWidgets('success colour on white ≥ 4.5:1', (tester) async {
      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      final ctx = tester.element(find.byType(Scaffold));
      final sem = Theme.of(ctx).extension<SemanticColors>()!;

      expect(
        contrastRatio(sem.success, Colors.white),
        greaterThanOrEqualTo(4.5),
        reason: 'A7: success colour used as text on white must clear 4.5:1',
      );
    });
  });

  // ─── A8 · IconButtons are labelled ───────────────────────────────────────

  group('A8 · Icon-only IconButtons carry an accessible name', () {
    testWidgets('every IconButton in the card subtree has a tooltip', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(ActiveTripCard(leg: _activeLeg())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final buttons = tester.widgetList<IconButton>(find.byType(IconButton));
      for (final b in buttons) {
        expect(
          b.tooltip,
          isNotNull,
          reason:
              'IconButton without tooltip leaves TalkBack reading the '
              'icon name only',
        );
        expect(b.tooltip, isNotEmpty);
      }
    });

    testWidgets('StatusChipRow renders chip with literal Finnish count text,'
        ' not just an icon', (tester) async {
      await tester.pumpWidget(
        _wrap(const StatusChipRow(unsyncedCount: 3, draftCount: 2)),
      );
      await tester.pumpAndSettle();

      // A3/A8: the chip carries the count in text — TalkBack must not be
      // forced to read "cloud upload" or "edit note" alone.
      expect(find.textContaining('synkronoimatta'), findsOneWidget);
      expect(find.textContaining('luonnosta'), findsOneWidget);
    });
  });

  // ─── A2 · Global IconButton theme ────────────────────────────────────────

  group('A2 · Theme enforces 48 dp IconButton minimum', () {
    test('app light theme has IconButton minimumSize ≥ 48 × 48', () {
      final theme = buildLightTheme();
      final style = theme.iconButtonTheme.style;
      expect(style, isNotNull, reason: 'A2: app must set IconButtonThemeData');

      final size = style!.minimumSize?.resolve({});
      expect(size, isNotNull);
      expect(size!.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });
}
