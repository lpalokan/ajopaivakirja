import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'services/location_service.dart';
import 'services/background_service.dart';
import 'services/sheets_service.dart';
import 'services/odometer_vision_service.dart';
import 'services/trip_detection_service.dart';
import 'services/file_opener_service.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

final backgroundServiceProvider = Provider<BackgroundService>((ref) {
  final ns = ref.watch(notificationServiceProvider);
  final ls = ref.watch(locationServiceProvider);
  return BackgroundService(notificationService: ns, locationService: ls);
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

// ── Theme extensions ───────────────────────────────────────────────────────

/// Semantic colour tokens beyond the Material 3 scheme.
@immutable
class SemanticColors extends ThemeExtension<SemanticColors> {
  final Color success;
  final Color successContainer;

  const SemanticColors({required this.success, required this.successContainer});

  @override
  SemanticColors copyWith({Color? success, Color? successContainer}) {
    return SemanticColors(
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
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

class KilometrikorvausApp extends StatelessWidget {
  const KilometrikorvausApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: const Color(0xFF1565C0),
            brightness: Brightness.light,
          ).copyWith(
            tertiary: const Color(0xFFB7793A),
            tertiaryContainer: const Color(0xFFFFDCBE),
            onTertiary: Colors.white,
          ),
      useMaterial3: true,
    );

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
      theme: baseTheme.copyWith(
        iconTheme: const IconThemeData(weight: 400, fill: 0, opticalSize: 24),
        extensions: <ThemeExtension<dynamic>>[
          NumeralTypography.standard(),
          const SemanticColors(
            success: Color(0xFF4C8C57),
            successContainer: Color(0xFFCDE7CF),
          ),
        ],
      ),
      darkTheme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: const Color(0xFF1565C0),
              brightness: Brightness.dark,
            ).copyWith(
              tertiary: const Color(0xFFB7793A),
              tertiaryContainer: const Color(0xFFFFDCBE),
              onTertiary: Colors.white,
            ),
        useMaterial3: true,
        extensions: <ThemeExtension<dynamic>>[
          NumeralTypography.standard(),
          const SemanticColors(
            success: Color(0xFF4C8C57),
            successContainer: Color(0xFFCDE7CF),
          ),
        ],
      ),
      home: const HomeScreen(),
    );
  }
}
