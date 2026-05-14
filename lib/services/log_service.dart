import 'dart:io';
import 'package:path_provider/path_provider.dart';

class LogService {
  static final LogService _instance = LogService._();
  factory LogService() => _instance;
  LogService._();

  String? _logPath;
  bool _enabled = false;

  bool get isEnabled => _enabled;

  Future<void> init({bool enabled = false}) async {
    _enabled = enabled;
    if (!_enabled) return;
    final dir = await getApplicationDocumentsDirectory();
    _logPath = '${dir.path}/kilometrikorvaus.log';
    await _write('=== Kilometrikorvaus log started ===');
    await _write('Time: ${DateTime.now()}');
  }

  void setEnabled(bool enabled) {
    _enabled = enabled;
    if (!enabled) _logPath = null;
  }

  Future<void> info(String message) async => _log('INFO', message);
  Future<void> warn(String message) async => _log('WARN', message);
  Future<void> error(String message, [Object? e, StackTrace? st]) async {
    var msg = message;
    if (e != null) msg += '\n  Error: $e';
    if (st != null) msg += '\n  Stack: $st';
    await _log('ERROR', msg);
  }

  Future<void> _log(String level, String message) async {
    if (!_enabled || _logPath == null) return;
    final ts = DateTime.now().toIso8601String();
    await _write('[$ts] $level: $message');
  }

  Future<void> _write(String line) async {
    try {
      final file = File(_logPath!);
      if (!file.existsSync()) {
        await file.create(recursive: true);
      }
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // Silently ignore write failures
    }
  }

  String? get logPath => _logPath;

  Future<String> readLogs() async {
    if (_logPath == null) return 'Logging not enabled';
    try {
      final file = File(_logPath!);
      if (!file.existsSync()) return 'No log file found';
      return file.readAsStringSync();
    } catch (e) {
      return 'Failed to read log: $e';
    }
  }
}
