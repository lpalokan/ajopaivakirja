import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/home_screen.dart';
import 'services/activity_recognition_service.dart';
import 'services/notification_service.dart';
import 'services/location_service.dart';
import 'services/background_service.dart';
import 'services/sheets_service.dart';
import 'services/odometer_vision_service.dart';
import 'services/trip_detection_service.dart';
import 'services/file_opener_service.dart';
import 'services/update_service.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

final activityRecognitionServiceProvider =
    Provider<ActivityRecognitionService>((ref) {
  return ActivityRecognitionService();
});

final backgroundServiceProvider = Provider<BackgroundService>((ref) {
  final ns = ref.watch(notificationServiceProvider);
  final ls = ref.watch(locationServiceProvider);
  final ars = ref.watch(activityRecognitionServiceProvider);
  return BackgroundService(
    notificationService: ns,
    locationService: ls,
    activityService: ars,
  );
});

final sheetsServiceProvider = Provider<SheetsService>((ref) {
  return SheetsService();
});

final odometerVisionServiceProvider = Provider<OdometerVisionService>((ref) {
  return OdometerVisionService();
});

final fileOpenerServiceProvider = Provider<FileOpenerService>((ref) {
  return FileOpenerService();
});

final tripDetectionServiceProvider = Provider<TripDetectionService>((ref) {
  final ls = ref.watch(locationServiceProvider);
  final ns = ref.watch(notificationServiceProvider);
  return TripDetectionService(locationService: ls, notificationService: ns);
});

final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService();
});

// ── Theme extensions ───────────────────────────────────────────────────────

/// Semantic colour tokens beyond the Material 3 scheme.
///
/// `onPrimaryMuted` (issue #46 A5) is used for de-emphasised text on the
/// active-trip gradient — explicit colour, not Opacity, so the contrast is
/// computable and survives Android 14 high-contrast text.
@immutable
class SemanticColors extends ThemeExtension<SemanticColors> {
  final Color success;
  final Color successContainer;
  final Color onPrimaryMuted;

  const SemanticColors({
    required this.success,
    required this.successContainer,
    required this.onPrimaryMuted,
  });

  @override
  SemanticColors copyWith({
    Color? success,
    Color? successContainer,
    Color? onPrimaryMuted,
  }) {
    return SemanticColors(
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      onPrimaryMuted: onPrimaryMuted ?? this.onPrimaryMuted,
    );
  }

  @override
  SemanticColors lerp(ThemeExtension<SemanticColors>? other, double t) {
    if (other is! SemanticColors) return this;
    return SemanticColors(
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onPrimaryMuted: Color.lerp(onPrimaryMuted, other.onPrimaryMuted, t)!,
    );
  }
}

/// Numeral typography scale — tabular figures for km/€ values (§8).
///
/// Access via `Theme.of(context).extension<NumeralTypography>()!`.
@immutable
class NumeralTypography extends ThemeExtension<NumeralTypography> {
  final TextStyle large; // 56/w700   active-trip distance
  final TextStyle medium; // 32/w600   StartCard odometer
  final TextStyle small; // 22/w600   history month totals, per-stop
  final TextStyle inline_; // 16/w600   today summary, per-row distances

  const NumeralTypography({
    required this.large,
    required this.medium,
    required this.small,
    required this.inline_,
  });

  factory NumeralTypography.standard() {
    return NumeralTypography(
      large: const TextStyle(
        fontSize: 56,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.02,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      medium: const TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.02,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      small: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.01,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      inline_: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }

  @override
  NumeralTypography copyWith({
    TextStyle? large,
    TextStyle? medium,
    TextStyle? small,
    TextStyle? inline_,
  }) {
    return NumeralTypography(
      large: large ?? this.large,
      medium: medium ?? this.medium,
      small: small ?? this.small,
      inline_: inline_ ?? this.inline_,
    );
  }

  @override
  NumeralTypography lerp(ThemeExtension<NumeralTypography>? other, double t) {
    if (other is! NumeralTypography) return this;
    return NumeralTypography(
      large: TextStyle.lerp(large, other.large, t)!,
      medium: TextStyle.lerp(medium, other.medium, t)!,
      small: TextStyle.lerp(small, other.small, t)!,
      inline_: TextStyle.lerp(inline_, other.inline_, t)!,
    );
  }
}

// ── App entry point ────────────────────────────────────────────────────────

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: KilometrikorvausApp()));
}

/// Light app theme. Top-level so accessibility tests can inspect it directly
/// without pumping the whole app (issue #46 A2/A7).
ThemeData buildLightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF1565C0),
    brightness: Brightness.light,
  ).copyWith(
    // A7: darkened from #B7793A (3.62:1) → ≈ 4.7:1 as text on white.
    tertiary: const Color(0xFF8E5618),
    tertiaryContainer: const Color(0xFFFFDCBE),
    onTertiary: Colors.white,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  return base.copyWith(
    iconTheme: const IconThemeData(weight: 400, fill: 0, opticalSize: 24),
    // A2: every IconButton has a ≥ 48 × 48 tappable area.
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    // A9: a visible focus indicator on dark and tinted surfaces alike.
    focusColor: const Color(0xFF1A1B20),
    extensions: <ThemeExtension<dynamic>>[
      NumeralTypography.standard(),
      const SemanticColors(
        // A7: darkened from #4C8C57 (4.04:1) → 6.8:1 on white.
        success: Color(0xFF2E6B3A),
        successContainer: Color(0xFFCDE7CF),
        // A5: holds ≈ 8.9:1 against the bottom of the active-trip gradient.
        onPrimaryMuted: Color(0xFFCCDBF6),
      ),
    ],
  );
}

ThemeData buildDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF1565C0),
    brightness: Brightness.dark,
  ).copyWith(
    tertiary: const Color(0xFFE0B17E),
    tertiaryContainer: const Color(0xFFFFDCBE),
    onTertiary: Colors.white,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  return base.copyWith(
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    extensions: <ThemeExtension<dynamic>>[
      NumeralTypography.standard(),
      const SemanticColors(
        success: Color(0xFF6FBF7B),
        successContainer: Color(0xFFCDE7CF),
        onPrimaryMuted: Color(0xFFCCDBF6),
      ),
    ],
  );
}

class KilometrikorvausApp extends StatelessWidget {
  const KilometrikorvausApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ajopäiväkirja',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fi'),
      supportedLocales: const [Locale('fi')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      home: const HomeScreen(),
    );
  }
}
