import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_version.dart';
import '../main.dart';
import '../models/update_info.dart';

/// Result of the latest `check` against the manifest:
/// - `null`        → up-to-date OR no check has run yet.
/// - non-null      → an update is available.
/// - `isLoading`   → a check is in flight.
/// - `hasError`    → the most recent check failed (offline, parse error, …).
typedef UpdateCheckState = AsyncValue<UpdateInfo?>;

class UpdateCheckNotifier extends StateNotifier<UpdateCheckState> {
  final Ref _ref;

  UpdateCheckNotifier(this._ref) : super(const AsyncValue.data(null));

  /// Runs a manifest check and folds the result into [state]. Errors
  /// are stored in [state] rather than thrown so the home banner and
  /// settings dialog can both surface them without separate plumbing.
  ///
  /// Guards each post-await `state =` with `mounted`: the home screen
  /// fires this from a postFrame callback, so a fast scenario teardown
  /// (or any first-frame disposal) can race the async check and try to
  /// land the result on an already-disposed notifier.
  Future<void> check() async {
    if (!mounted) return;
    state = const AsyncValue.loading();
    try {
      final service = _ref.read(updateServiceProvider);
      final info = await service.checkForUpdate(
        currentBuildNumber: appBuildNumber,
        useReleaseChannel: kReleaseMode,
      );
      if (!mounted) return;
      state = AsyncValue.data(info);
    } catch (e, st) {
      if (!mounted) return;
      state = AsyncValue.error(e, st);
    }
  }

  /// Hands the already-fetched [UpdateInfo] off to the install flow, surfacing
  /// download progress through [updateDownloadProgressProvider] so the banner
  /// and settings tile can show a spinner/progress bar instead of looking
  /// frozen while a multi-megabyte APK downloads.
  ///
  /// No-op if no update is currently known, or if a download is already in
  /// flight (guards against double taps queuing a second download).
  Future<void> install() async {
    final info = state.value;
    if (info == null) return;
    final progress = _ref.read(updateDownloadProgressProvider.notifier);
    if (progress.state != null) return;
    final service = _ref.read(updateServiceProvider);
    progress.state = UpdateDownloadProgress.indeterminate;
    try {
      await service.downloadAndInstall(
        info,
        onProgress: (received, total) {
          progress.state = (total != null && total > 0)
              ? received / total
              : UpdateDownloadProgress.indeterminate;
        },
      );
    } finally {
      // Download finished (or threw): the system installer now owns the
      // foreground, so clear the in-app progress either way.
      progress.state = null;
    }
  }
}

/// Download progress for an in-flight install, or `null` when no download is
/// running. A value in `0.0..1.0` is determinate; [UpdateDownloadProgress
/// .indeterminate] (`-1`) means the server gave no Content-Length, so the UI
/// should show an indeterminate spinner.
final updateDownloadProgressProvider = StateProvider<double?>((ref) => null);

/// Sentinel value namespace for [updateDownloadProgressProvider].
abstract final class UpdateDownloadProgress {
  /// Downloading, but total size unknown — show an indeterminate indicator.
  static const double indeterminate = -1;
}

final updateCheckProvider =
    StateNotifierProvider<UpdateCheckNotifier, UpdateCheckState>((ref) {
  return UpdateCheckNotifier(ref);
});
