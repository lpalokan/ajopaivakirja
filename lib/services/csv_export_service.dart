import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../models/trip_leg.dart';

class CsvExportService {
  /// Generate CSV content string for the given legs.
  static String generateContent(List<TripLeg> legs) {
    final buf = StringBuffer();

    // Header
    buf.writeln(_header());

    // Rows, sorted by date then leg order
    final sorted = List<TripLeg>.from(legs)
      ..sort((a, b) {
        final dateCmp = a.date.compareTo(b.date);
        if (dateCmp != 0) return dateCmp;
        return a.legOrder.compareTo(b.legOrder);
      });

    for (final leg in sorted) {
      buf.writeln(_row(leg));
    }

    return buf.toString();
  }

  /// Generate a CSV file for the given legs.
  /// Returns the file path.
  static Future<File> generate({
    required List<TripLeg> legs,
    String? fileName,
  }) async {
    final content = generateContent(legs);

    // Save to documents directory
    final dir = await getApplicationDocumentsDirectory();
    final name = fileName ?? 'ajopaivakirja_export_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
    final file = File('${dir.path}/$name');
    await file.writeAsString(content);
    return file;
  }

  static String _header() {
    return [
      'Päivämäärä',
      'Järjestys',
      'Lähtöaika',
      'Päättymisaika',
      'Lähtöpaikka',
      'Määränpää',
      'Reitti',
      'Mittari alussa',
      'Mittari lopussa',
      'Ajetut km',
      'Tarkoitus',
      'Kuljettaja',
      'Km-korvaus (€)',
      'Päiväraha (€)',
      'Päivärahatyyppi',
      'Kotiinpaluu',
    ].join(',');
  }

  static String _row(TripLeg leg) {
    final timeFmt = DateFormat('HH:mm');
    final dailyTypeStr = switch (leg.dailyAllowanceType) {
      0 => 'Ei päivärahaa',
      1 => 'Puolipäivä (>6h)',
      2 => 'Kokopäivä (>10h)',
      _ => 'Automaattinen',
    };

    return _csvLine([
      leg.date,
      leg.legOrder.toString(),
      timeFmt.format(leg.startTime),
      leg.endTime != null ? timeFmt.format(leg.endTime!) : '',
      _escape(leg.startLocation),
      _escape(leg.endLocation ?? ''),
      _escape(leg.routeDescription ?? ''),
      leg.startOdometer.toString(),
      leg.endOdometer?.toString() ?? '',
      leg.kmDriven.toStringAsFixed(1),
      _escape(leg.purpose ?? ''),
      _escape(leg.driver),
      leg.kmAllowance.toStringAsFixed(2),
      leg.dailyAllowance.toStringAsFixed(2),
      dailyTypeStr,
      leg.isReturnHome ? 'Kyllä' : 'Ei',
    ]);
  }

  static String _csvLine(List<String> values) {
    return values.join(',');
  }

  static String _escape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
