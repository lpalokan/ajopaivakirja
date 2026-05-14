import 'package:http/http.dart' as http;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/auth_io.dart';
import '../models/trip_leg.dart';
import 'log_service.dart';

class SheetsService {
  final GoogleSignIn _googleSignIn;
  sheets.SheetsApi? _sheetsApi;
  http.Client? _authClient;

  SheetsService()
      : _googleSignIn = GoogleSignIn(
          scopes: [sheets.SheetsApi.spreadsheetsScope],
        );

  bool isConfigured(String sheetId) => sheetId.isNotEmpty;

  Future<bool> get isSignedIn => _googleSignIn.isSignedIn();

  Future<void> signIn() async {
    try {
      LogService().info('Google Sign-In: starting...');
      final account = await _googleSignIn.signIn();
      if (account == null) {
        LogService().warn('Google Sign-In: cancelled by user');
        throw Exception('Kirjautuminen peruttu');
      }
      LogService().info('Google Sign-In: got account (${account.email})');

      final authHeaders = await account.authHeaders;
      LogService().info('Google Sign-In: got auth headers');
    final credentials = AccessCredentials(
      AccessToken(
        'Bearer',
        authHeaders['Authorization']!.replaceFirst('Bearer ', ''),
        DateTime.now().add(const Duration(hours: 1)),
      ),
      null,
      [sheets.SheetsApi.spreadsheetsScope],
    );

    final client = GoogleAuthClient(credentials, http.Client());
    _authClient = client;
    _sheetsApi = sheets.SheetsApi(client);
    LogService().info('Google Sign-In: success');
    } catch (e, st) {
      LogService().error('Google Sign-In failed', e, st);
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _authClient?.close();
    _authClient = null;
    _sheetsApi = null;
  }

  /// Append a single trip leg as a row in Google Sheets.
  Future<void> appendLeg(TripLeg leg, {required String sheetId, required String sheetTab}) async {
    if (_sheetsApi == null) {
      throw Exception('Ei kirjauduttu Googleen. Kirjaudu asetuksista.');
    }
    if (sheetId.isEmpty) {
      throw Exception('Google Sheets -tunnusta ei ole määritetty asetuksissa.');
    }

    final range = '$sheetTab!A1:P1';

    final row = _legToRow(leg);

    final valueRange = sheets.ValueRange()
      ..range = range
      ..values = [row];

    LogService().info('Sheets append: ${leg.startLocation} -> ${leg.endLocation}, ${leg.kmDriven}km');
    await _sheetsApi!.spreadsheets.values.append(
      valueRange,
      sheetId,
      range,
      valueInputOption: 'USER_ENTERED',
      insertDataOption: 'INSERT_ROWS',
    );
  }

  /// Append multiple legs, optionally marking them as synced.
  Future<int> appendLegs(
    List<TripLeg> legs, {
    required String sheetId,
    required String sheetTab,
    Future<void> Function(int legId)? onSynced,
  }) async {
    var synced = 0;
    for (final leg in legs) {
      try {
        await appendLeg(leg, sheetId: sheetId, sheetTab: sheetTab);
        await onSynced?.call(leg.id!);
        synced++;
      } catch (e) {
        rethrow;
      }
    }
    return synced;
  }

  List<Object?> _legToRow(TripLeg leg) {
    final startTime = leg.startTime;
    final endTime = leg.endTime;
    final dateFormat = _formatDate(startTime);
    final startTimeStr = _formatTime(startTime);
    final endTimeStr = endTime != null ? _formatTime(endTime) : '';

    return [
      dateFormat,
      startTimeStr,
      leg.startOdometer,
      endTimeStr,
      leg.endOdometer ?? '',
      leg.startLocation,
      leg.endLocation ?? '',
      leg.routeDescription ?? '',
      leg.kmDriven,
      leg.purpose ?? '',
      leg.driver,
      leg.kmAllowance,
      leg.dailyAllowance,
      leg.totalAllowance,
      leg.legDurationHours,
      leg.workingTimeHours,
    ];
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}.${dt.month}.${dt.year}';
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void dispose() {
    _authClient?.close();
    _authClient = null;
    _sheetsApi = null;
  }
}

class GoogleAuthClient extends http.BaseClient {
  final AccessCredentials _credentials;
  final http.Client _inner;

  GoogleAuthClient(this._credentials, this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers['Authorization'] =
        'Bearer ${_credentials.accessToken.data}';
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
