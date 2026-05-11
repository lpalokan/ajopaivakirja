import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_settings.dart';
import '../services/database_service.dart';

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings());

  Future<void> load() async {
    try {
      state = await DatabaseService.loadSettings();
    } catch (_) {
      state = const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    state = settings;
    await DatabaseService.saveSettings(settings);
  }

  Future<void> update(Map<String, String?> fields) async {
    var s = state;
    if (fields.containsKey('home_location') && fields['home_location'] != null) {
      s = s.copyWith(homeLocation: fields['home_location']!);
    }
    if (fields.containsKey('km_rate') && fields['km_rate'] != null) {
      s = s.copyWith(
          kmRate: double.tryParse(fields['km_rate']!) ?? s.kmRate);
    }
    if (fields.containsKey('allowance_6h') && fields['allowance_6h'] != null) {
      s = s.copyWith(
          allowance6h:
              double.tryParse(fields['allowance_6h']!) ?? s.allowance6h);
    }
    if (fields.containsKey('allowance_10h') &&
        fields['allowance_10h'] != null) {
      s = s.copyWith(
          allowance10h:
              double.tryParse(fields['allowance_10h']!) ?? s.allowance10h);
    }
    if (fields.containsKey('sheet_id') && fields['sheet_id'] != null) {
      s = s.copyWith(sheetId: fields['sheet_id']!);
    }
    if (fields.containsKey('sheet_tab') && fields['sheet_tab'] != null) {
      s = s.copyWith(sheetTab: fields['sheet_tab']!);
    }
    if (fields.containsKey('driver_name') && fields['driver_name'] != null) {
      s = s.copyWith(driverName: fields['driver_name']!);
    }
    await save(s);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});
