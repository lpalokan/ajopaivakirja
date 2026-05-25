import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../models/update_info.dart';

/// Polls the GitHub-hosted update manifest, compares the published
/// buildNumber against the running app's [appBuildNumber], and if a
/// newer build exists downloads the matching APK and hands it to the
/// Android package installer.
///
/// The manifest is a single small JSON file with both `release` and
/// `debug` channels; the caller picks the channel based on
/// `kReleaseMode`. APK assets live under a rolling GitHub Release tag
/// (`latest`) so the URLs are stable across versions.
class UpdateService {
  /// Where the manifest lives. Hosted as a release asset so we don't
  /// have to round-trip through the GitHub API (no rate limits, no
  /// auth) and the URL never changes.
  static const String manifestUrl =
      'https://github.com/lpalokan/ajopaivakirja/releases/download/latest/manifest.json';

  /// Returns the available update for the given channel, or `null` if
  /// the manifest's buildNumber is `<=` [currentBuildNumber] (i.e. the
  /// running app is already on the latest build).
  ///
  /// Throws on network/parse failures; callers (the notifier in
  /// particular) should surface these as a non-blocking error so the
  /// app keeps working when offline.
  Future<UpdateInfo?> checkForUpdate({
    required int currentBuildNumber,
    required bool useReleaseChannel,
  }) async {
    final response = await http.get(Uri.parse(manifestUrl));
    if (response.statusCode != 200) {
      throw HttpException(
        'Manifest fetch failed: HTTP ${response.statusCode}',
      );
    }
    final manifest = jsonDecode(response.body) as Map<String, dynamic>;
    final channel = manifest[useReleaseChannel ? 'release' : 'debug']
        as Map<String, dynamic>?;
    if (channel == null) {
      throw const FormatException(
        'Manifest is missing the requested channel',
      );
    }
    final info = UpdateInfo.fromJson(channel);
    if (info.buildNumber <= currentBuildNumber) return null;
    return info;
  }

  /// Downloads the APK to the app's cache dir and asks Android to open
  /// it — which routes through the system package installer. On first
  /// invocation Android will prompt the user to enable "Install
  /// unknown apps" for this source (post-API-26 requirement). The
  /// signing certificate on the downloaded APK must match the
  /// installed one or Android refuses with "App not installed"; the
  /// release-signing CI step guarantees this for release builds.
  Future<void> downloadAndInstall(UpdateInfo info) async {
    final response = await http.get(Uri.parse(info.apkUrl));
    if (response.statusCode != 200) {
      throw HttpException('APK download failed: HTTP ${response.statusCode}');
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/update-${info.buildNumber}.apk');
    await file.writeAsBytes(response.bodyBytes, flush: true);
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      throw Exception(
        'Could not launch installer: ${result.message}',
      );
    }
  }
}
