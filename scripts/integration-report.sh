#!/usr/bin/env bash
#
# Runs the end-to-end use-case suite on an Android emulator and writes a
# self-contained report you can hand back for analysis.
#
#   ./scripts/integration-report.sh
#
# Output: reports/integration-report-<timestamp>.txt
#
# Boots the 'test_pixel' AVD if no device is attached. Does not install the
# Flutter or Android SDK; it locates the Android SDK and checks tools.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

AVD_NAME="test_pixel"
ANDROID_API="34"
TS="$(date +%Y%m%d-%H%M%S)"
REPORT_DIR="$REPO_ROOT/reports"
REPORT="$REPORT_DIR/integration-report-$TS.txt"
mkdir -p "$REPORT_DIR"

info() { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$1"; }
fail() { printf '\033[1;31m  ✗\033[0m %s\n' "$1" >&2; }

require() {
  command -v "$1" >/dev/null 2>&1 || { fail "'$1' not found. $2"; exit 1; }
}

info "Checking prerequisites"
require flutter "Install Flutter 3.11+."
require java    "Install a JDK 17+."

# Locate the Android SDK and expose its tool dirs.
SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [ -z "$SDK_ROOT" ]; then
  for cand in "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    [ -d "$cand" ] && SDK_ROOT="$cand" && break
  done
fi
[ -n "$SDK_ROOT" ] && [ -d "$SDK_ROOT" ] || {
  fail "Android SDK not found. Set ANDROID_SDK_ROOT."; exit 1; }
export ANDROID_SDK_ROOT="$SDK_ROOT"
for d in emulator platform-tools cmdline-tools/latest/bin tools/bin; do
  [ -d "$SDK_ROOT/$d" ] && PATH="$SDK_ROOT/$d:$PATH"
done
export PATH
require adb "Android platform-tools missing from the SDK."
ok "Android SDK: $SDK_ROOT"

# Boot an emulator only if no device/emulator is already online.
EMULATOR_PID=""
if ! adb devices | awk 'NR>1 && $2=="device"{found=1} END{exit !found}'; then
  require emulator "Install the Android 'emulator' package."
  require avdmanager "Install Android cmdline-tools."
  require sdkmanager "Install Android cmdline-tools."
  case "$(uname -m)" in
    arm64|aarch64) ABI="arm64-v8a" ;;
    *)             ABI="x86_64" ;;
  esac
  IMAGE="system-images;android-${ANDROID_API};google_apis;${ABI}"
  sdkmanager --list_installed 2>/dev/null | grep -q "${IMAGE}" || {
    info "Installing ${IMAGE}"; yes | sdkmanager "platform-tools" "emulator" "${IMAGE}"; }
  avdmanager list avd 2>/dev/null | grep -q "Name: ${AVD_NAME}" || {
    info "Creating AVD '${AVD_NAME}'"
    echo "no" | avdmanager create avd -n "${AVD_NAME}" -k "${IMAGE}" -d pixel_6; }
  info "Booting emulator '${AVD_NAME}'"
  emulator -avd "${AVD_NAME}" -no-snapshot -no-boot-anim -netdelay none \
    -netspeed full >/tmp/ajopaivakirja-emulator.log 2>&1 &
  EMULATOR_PID=$!
  trap '[ -n "$EMULATOR_PID" ] && kill "$EMULATOR_PID" 2>/dev/null || true' EXIT
  adb wait-for-device
  until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d "\r")" = "1" ]; do
    sleep 2
  done
  ok "Emulator booted."
else
  ok "Using already-attached device/emulator."
fi

# ── Build the report ───────────────────────────────────────────────────────

DEVICE_PROPS="$(adb shell getprop ro.build.version.release 2>/dev/null | tr -d '\r') / API $(adb shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r') / $(adb shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r')"

{
  echo "==================================================================="
  echo " Ajopäiväkirja — End-to-end use-case test report"
  echo "==================================================================="
  echo "Timestamp     : $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "Git branch    : $(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  echo "Git commit    : $(git rev-parse --short HEAD 2>/dev/null)"
  echo "Flutter       : $(flutter --version 2>/dev/null | head -1)"
  echo "Emulator      : Android $DEVICE_PROPS"
  echo "Suite         : integration_test/app_use_cases_test.dart"
  echo "==================================================================="
  echo
  echo "----- flutter analyze (advisory) ----------------------------------"
  flutter analyze 2>&1 | tail -8
  echo
  echo "----- integration_test (emulator) ---------------------------------"
} | tee "$REPORT"

info "Running use-case suite on the emulator"
set -o pipefail
flutter test integration_test/app_use_cases_test.dart --reporter expanded 2>&1 \
  | tee -a "$REPORT"
RESULT=${PIPESTATUS[0]}

{
  echo
  echo "----- result ------------------------------------------------------"
  if [ "$RESULT" -eq 0 ]; then
    echo "STATUS: PASS (all use-case tests passed)"
  else
    echo "STATUS: FAIL (exit $RESULT) — see per-test output above"
  fi
  echo "==================================================================="
} | tee -a "$REPORT"

info "Report written to: $REPORT"
echo "Pass this file back for analysis:"
echo "  $REPORT"
exit "$RESULT"
