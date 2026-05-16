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

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

final backgroundServiceProvider = Provider<BackgroundService>((ref) {
  final ns = ref.watch(notificationServiceProvider);
  final ls = ref.watch(locationServiceProvider);
  return BackgroundService(
    notificationService: ns,
    locationService: ls,
  );
});

final sheetsServiceProvider = Provider<SheetsService>((ref) {
  return SheetsService();
});

final odometerVisionServiceProvider = Provider<OdometerVisionService>((ref) {
  return OdometerVisionService();
});

final tripDetectionServiceProvider = Provider<TripDetectionService>((ref) {
  final ls = ref.watch(locationServiceProvider);
  final ns = ref.watch(notificationServiceProvider);
  return TripDetectionService(
    locationService: ls,
    notificationService: ns,
  );
});

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: KilometrikorvausApp()));
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
