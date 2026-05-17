import 'package:flutter/foundation.dart';

class AppSettings {
  final String homeLocation;
  final double kmRate;
  final double allowance6h;
  final double allowance10h;
  final String sheetId;
  final String sheetTab;
  final String driverName;
  final bool debugLogging;

  const AppSettings({
    this.homeLocation = 'Koti',
    this.kmRate = 0.57,
    this.allowance6h = 25.0,
    this.allowance10h = 54.0,
    this.sheetId = '',
    this.sheetTab = 'Taulukko1',
    this.driverName = kDebugMode ? 'Lapa' : '',
    this.debugLogging = false,
  });

  AppSettings copyWith({
    String? homeLocation,
    double? kmRate,
    double? allowance6h,
    double? allowance10h,
    String? sheetId,
    String? sheetTab,
    String? driverName,
    bool? debugLogging,
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
    };
  }

  factory AppSettings.fromMap(Map<String, String> map) {
    return AppSettings(
      homeLocation: map['home_location'] ?? 'Koti',
      kmRate: double.tryParse(map['km_rate'] ?? '') ?? 0.57,
      allowance6h: double.tryParse(map['allowance_6h'] ?? '') ?? 25.0,
      allowance10h: double.tryParse(map['allowance_10h'] ?? '') ?? 54.0,
      sheetId: map['sheet_id'] ?? '',
      sheetTab: map['sheet_tab'] ?? 'Taulukko1',
      driverName: map['driver_name'] ?? '',
      debugLogging: map['debug_logging'] == '1',
    );
  }

  Map<String, dynamic> toJson() => toMap();

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      AppSettings.fromMap(json.map((k, v) => MapEntry(k, v.toString())));

  @override
  String toString() =>
      'AppSettings(km: $kmRate€, 6h: $allowance6h€, 10h: $allowance10h€, driver: $driverName)';
}
