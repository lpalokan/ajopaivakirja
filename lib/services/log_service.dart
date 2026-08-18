import 'dart:io';
import 'package:path_provider/path_provider.dart';

class LogService {
  static final LogService _instance = LogService._();
  factory LogService() => _instance;
  LogService._();

  /// Rotate once the file grows past this. A multi-hour drive with GPS and
  /// reminder-tick lines must stay small enough to attach to a message; the
  /// previous log survives as [rotatedLogSuffix] so rotation mid-drive never
  /// discards the window where a bug actually happened.
  static const int maxLogBytes = 512 * 1024;

  /// Appended to [logPath] for the rotated-out previous log.
  static const String rotatedLogSuffix = '.1';

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

  /// Enables logging in a secondary isolate — the flutter_local_notifications
  /// background isolate that handles the "Ajan yhä" tap — but only when the
  /// main app has logging switched on. Each isolate gets its own [LogService]
  /// singleton, so without this the tap handling is invisible in the shared
  /// log and "the reminder came back even though I tapped Ajan yhä" cannot be
  /// told apart from "the tap never reached the handler". The log file's
  /// existence is the cross-isolate signal that logging is on: it is created
  /// on enable and deleted when the user disables logging.
  Future<void> initForBackgroundIsolate() async {
    if (_enabled) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/kilometrikorvaus.log';
      if (File(path).existsSync()) {
        _logPath = path;
        _enabled = true;
      }
    } catch (_) {
      // Logging stays off in this isolate; the tap still works.
    }
  }

  void setEnabled(bool enabled) {
    _enabled = enabled;
    if (!enabled) {
      // Remove the files so the background isolate's existence check (see
      // [initForBackgroundIsolate]) turns off with the setting.
      final path = _logPath;
      _logPath = null;
      if (path != null) {
        try {
          final file = File(path);
          if (file.existsSync()) file.deleteSync();
          final rotated = File('$path$rotatedLogSuffix');
          if (rotated.existsSync()) rotated.deleteSync();
        } catch (_) {}
      }
    }
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
      } else if (file.lengthSync() > maxLogBytes) {
        // Rotate: keep the full previous window as `.1` rather than
        // truncating, so the moments leading up to a bug survive rotation.
        final rotated = File('${_logPath!}$rotatedLogSuffix');
        if (rotated.existsSync()) rotated.deleteSync();
        file.renameSync(rotated.path);
        await File(_logPath!).create(recursive: true);
      }
      await File(_logPath!)
          .writeAsString('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // Silently ignore write failures
    }
  }

  String? get logPath => _logPath;

  Future<String> readLogs() async {
    if (_logPath == null) return 'Logging not enabled';
    try {
      // Prepend the rotated-out previous window (if any) so a share after an
      // in-drive rotation still carries the whole story.
      final rotated = File('${_logPath!}$rotatedLogSuffix');
      final older = rotated.existsSync() ? rotated.readAsStringSync() : '';
      final file = File(_logPath!);
      if (!file.existsSync() && older.isEmpty) return 'No log file found';
      final current = file.existsSync() ? file.readAsStringSync() : '';
      return '$older$current';
    } catch (e) {
      return 'Failed to read log: $e';
    }
  }
}
