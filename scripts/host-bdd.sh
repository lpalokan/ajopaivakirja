#!/usr/bin/env bash
# Run the BDD integration suite HEADLESS — on the flutter "tester" (host),
# with no Android emulator. Use this when an emulator isn't available (e.g. an
# environment with no KVM/hardware virtualization, where an Android AVD can't
# run at all).
#
#   scripts/host-bdd.sh                       # whole suite
#   scripts/host-bdd.sh --plain-name "defer"  # one scenario (substring match)
#
# How it works: tool/bdd_host_test.dart imports the build_runner-generated
# feature tests and runs them on the host, backing sqflite with
# sqflite_common_ffi (over libsqlite3) and mocking the geolocator plugin
# channels. See docs/testing.md → "Running without an emulator".
#
# The on-emulator suite (scripts/integration-report.sh) is still the source of
# truth. A few device-only checks are intentionally excluded here (see the
# header of tool/bdd_host_test.dart).
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter not on PATH — run scripts/setup-test-env.sh first." >&2
  exit 1
fi

if ! ldconfig -p 2>/dev/null | grep -q libsqlite3; then
  echo "WARNING: libsqlite3 not found; sqflite_common_ffi needs it." >&2
  echo "  Install with: apt-get install -y libsqlite3-0" >&2
fi

# Keep the generated feature tests in sync with the .feature sources.
dart run build_runner build --delete-conflicting-outputs

exec flutter test tool/bdd_host_test.dart "$@"
