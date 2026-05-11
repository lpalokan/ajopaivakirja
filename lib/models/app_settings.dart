class AppSettings {
  final String homeLocation;
  final double kmRate;
  final double allowance6h;
  final double allowance10h;
  final String sheetId;
  final String sheetTab;
  final String driverName;

  const AppSettings({
    this.homeLocation = 'Koti',
    this.kmRate = 0.57,
    this.allowance6h = 24.0,
    this.allowance10h = 48.0,
    this.sheetId = '',
    this.sheetTab = 'Sheet1',
    this.driverName = '',
  });

  AppSettings copyWith({
    String? homeLocation,
    double? kmRate,
    double? allowance6h,
    double? allowance10h,
    String? sheetId,
    String? sheetTab,
    String? driverName,
  }) {
    return AppSettings(
      homeLocation: homeLocation ?? this.homeLocation,
      kmRate: kmRate ?? this.kmRate,
      allowance6h: allowance6h ?? this.allowance6h,
      allowance10h: allowance10h ?? this.allowance10h,
      sheetId: sheetId ?? this.sheetId,
      sheetTab: sheetTab ?? this.sheetTab,
      driverName: driverName ?? this.driverName,
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
    };
  }

  factory AppSettings.fromMap(Map<String, String> map) {
    return AppSettings(
      homeLocation: map['home_location'] ?? 'Koti',
      kmRate: double.tryParse(map['km_rate'] ?? '') ?? 0.57,
      allowance6h: double.tryParse(map['allowance_6h'] ?? '') ?? 24.0,
      allowance10h: double.tryParse(map['allowance_10h'] ?? '') ?? 48.0,
      sheetId: map['sheet_id'] ?? '',
      sheetTab: map['sheet_tab'] ?? 'Sheet1',
      driverName: map['driver_name'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => toMap();

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      AppSettings.fromMap(json.map((k, v) => MapEntry(k, v.toString())));

  @override
  String toString() =>
      'AppSettings(km: $kmRate€, 6h: $allowance6h€, 10h: $allowance10h€, driver: $driverName)';
}
