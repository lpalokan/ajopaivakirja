/// Single channel's worth of info parsed out of the GitHub-hosted
/// update manifest (`dist/latest.json` published by .github/workflows/
/// release.yml on every push to main).
class UpdateInfo {
  final int buildNumber;
  final String version;
  final String apkUrl;
  final DateTime publishedAt;

  UpdateInfo({
    required this.buildNumber,
    required this.version,
    required this.apkUrl,
    required this.publishedAt,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      buildNumber: json['buildNumber'] as int,
      version: json['version'] as String,
      apkUrl: json['apkUrl'] as String,
      publishedAt: DateTime.parse(json['publishedAt'] as String),
    );
  }
}
