import 'package:flutter/foundation.dart';

class AppSettings {
  // ── Auto-detection thresholds (issue #52) ────────────────────────────────
  //
  // GPS trip auto-detection used to run on constants baked into
  // DetectionConfig. They are a compromise: a threshold that works in city
  // traffic misfires on a bicycle commute, and one tuned for motorway driving
  // never notices a short errand. These bounds keep the user's choice inside
  // the range the detector behaves sensibly in.
  static const double defaultDetectionSpeedMps = 5.0;
  static const double minDetectionSpeedMps = 3.0;
  static const double maxDetectionSpeedMps = 8.0;

  static const int defaultDetectionDrivingSeconds = 30;
  static const int minDetectionDrivingSeconds = 15;
  static const int maxDetectionDrivingSeconds = 120;

  static const int defaultDetectionArrivalSeconds = 60;
  static const int minDetectionArrivalSeconds = 30;
  static const int maxDetectionArrivalSeconds = 180;

  final String homeLocation;
  final double kmRate;
  final double allowance6h;
  final double allowance10h;
  final String sheetId;
  final String sheetTab;
  final String driverName;
  final bool debugLogging;

  /// Whether the app watches GPS for the start of a drive at all.
  ///
  /// On by default, so nothing changes for anyone who never opens this. Off
  /// is for drivers who start every trip by hand and would rather the app
  /// did not hold a position stream open while it waits for one.
  final bool autoDetect;

  /// Speed (m/s) at or above which the device counts as "moving fast" for
  /// auto-detection.
  final double detectionSpeedMps;

  /// How long that fast movement must be sustained before a trip is detected.
  final int detectionDrivingSeconds;

  /// How long the vehicle must stay stopped before arrival is detected.
  final int detectionArrivalSeconds;

  const AppSettings({
    this.homeLocation = 'Koti',
    this.kmRate = 0.55,
    this.allowance6h = 25.0,
    this.allowance10h = 54.0,
    this.sheetId = '',
    this.sheetTab = 'Taulukko1',
    this.driverName = kDebugMode ? 'Lapa' : '',
    this.debugLogging = false,
    this.autoDetect = true,
    this.detectionSpeedMps = defaultDetectionSpeedMps,
    this.detectionDrivingSeconds = defaultDetectionDrivingSeconds,
    this.detectionArrivalSeconds = defaultDetectionArrivalSeconds,
  });

  /// Clamp a stored/entered speed threshold into the supported range.
  static double clampDetectionSpeed(double mps) =>
      mps.clamp(minDetectionSpeedMps, maxDetectionSpeedMps).toDouble();

  /// Clamp a stored/entered sustained-driving duration into range.
  static int clampDetectionDrivingSeconds(int seconds) =>
      seconds.clamp(minDetectionDrivingSeconds, maxDetectionDrivingSeconds);

  /// Clamp a stored/entered arrival-stop duration into range.
  static int clampDetectionArrivalSeconds(int seconds) =>
      seconds.clamp(minDetectionArrivalSeconds, maxDetectionArrivalSeconds);

  AppSettings copyWith({
    String? homeLocation,
    double? kmRate,
    double? allowance6h,
    double? allowance10h,
    String? sheetId,
    String? sheetTab,
    String? driverName,
    bool? debugLogging,
    bool? autoDetect,
    double? detectionSpeedMps,
    int? detectionDrivingSeconds,
    int? detectionArrivalSeconds,
  }) {
    return AppSettings(
      homeLocation: homeLocation ?? this.homeLocation,
      kmRate: kmRate ?? this.kmRate,
      allowance6h: allowance6h ?? this.allowance6h,
      allowance10h: allowance10h ?? this.allowance10h,
      sheetId: sheetId ?? this.sheetId,
      sheetTab: sheetTab ?? this.sheetTab,
      driverName: driverName ?? this.driverName,
      debugLogging: debugLogging ?? this.debugLogging,
      autoDetect: autoDetect ?? this.autoDetect,
      detectionSpeedMps: detectionSpeedMps ?? this.detectionSpeedMps,
      detectionDrivingSeconds:
          detectionDrivingSeconds ?? this.detectionDrivingSeconds,
      detectionArrivalSeconds:
          detectionArrivalSeconds ?? this.detectionArrivalSeconds,
    );
  }

  Map<String, String> toMap() {
    return {
      'home_location': homeLocation,
      'km_rate': kmRate.toString(),
      'allowance_6h': allowance6h.toString(),
      'allowance_10h': allowance10h.toString(),
      'sheet_id': sheetId,
      'sheet_tab': sheetTab,
      'driver_name': driverName,
      'debug_logging': debugLogging ? '1' : '0',
      'auto_detect': autoDetect ? '1' : '0',
      'detection_speed_mps': detectionSpeedMps.toString(),
      'detection_driving_seconds': detectionDrivingSeconds.toString(),
      'detection_arrival_seconds': detectionArrivalSeconds.toString(),
    };
  }

  factory AppSettings.fromMap(Map<String, String> map) {
    return AppSettings(
      homeLocation: map['home_location'] ?? 'Koti',
      kmRate: double.tryParse(map['km_rate'] ?? '') ?? 0.55,
      allowance6h: double.tryParse(map['allowance_6h'] ?? '') ?? 25.0,
      allowance10h: double.tryParse(map['allowance_10h'] ?? '') ?? 54.0,
      sheetId: map['sheet_id'] ?? '',
      sheetTab: map['sheet_tab'] ?? 'Taulukko1',
      driverName: map['driver_name'] ?? '',
      debugLogging: map['debug_logging'] == '1',
      // Absent means on: an install that predates the toggle keeps the
      // behaviour it already had.
      autoDetect: (map['auto_detect'] ?? '1') != '0',
      // Clamped on the way in: a value written by an older/newer build, or a
      // hand-edited row, must not push the detector outside the range it was
      // tuned for.
      detectionSpeedMps: clampDetectionSpeed(
        double.tryParse(map['detection_speed_mps'] ?? '') ??
            defaultDetectionSpeedMps,
      ),
      detectionDrivingSeconds: clampDetectionDrivingSeconds(
        int.tryParse(map['detection_driving_seconds'] ?? '') ??
            defaultDetectionDrivingSeconds,
      ),
      detectionArrivalSeconds: clampDetectionArrivalSeconds(
        int.tryParse(map['detection_arrival_seconds'] ?? '') ??
            defaultDetectionArrivalSeconds,
      ),
    );
  }

  Map<String, dynamic> toJson() => toMap();

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      AppSettings.fromMap(json.map((k, v) => MapEntry(k, v.toString())));

  @override
  String toString() =>
      'AppSettings(km: $kmRate€, 6h: $allowance6h€, 10h: $allowance10h€, driver: $driverName)';
}
