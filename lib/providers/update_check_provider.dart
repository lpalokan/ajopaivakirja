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

  /// Hands the already-fetched [UpdateInfo] off to the install flow.
  /// No-op if no update is currently known.
  Future<void> install() async {
    final info = state.value;
    if (info == null) return;
    final service = _ref.read(updateServiceProvider);
    await service.downloadAndInstall(info);
  }
}

final updateCheckProvider =
    StateNotifierProvider<UpdateCheckNotifier, UpdateCheckState>((ref) {
  return UpdateCheckNotifier(ref);
});
