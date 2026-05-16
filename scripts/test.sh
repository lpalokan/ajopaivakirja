#!/usr/bin/env bash
#
# Local test setup + runner for the Ajopäiväkirja app.
#
#   ./scripts/test.sh              Run host tests (pub get, analyze, flutter test)
#   ./scripts/test.sh --emulator   Also provision an AVD and run the emulator
#                                   integration smoke test
#   ./scripts/test.sh --help
#
# Idempotent: safe to re-run. Does NOT install the Flutter SDK or Android
# SDK (those are large, OS-specific installs) — it checks for them and tells
# you what is missing.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

AVD_NAME="test_pixel"
ANDROID_API="34"

RUN_EMULATOR=0
for arg in "$@"; do
  case "$arg" in
    --emulator) RUN_EMULATOR=1 ;;
    --help|-h)
      sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
  esac
done

info()  { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }
ok()    { printf '\033[1;32m  ✓\033[0m %s\n' "$1"; }
fail()  { printf '\033[1;31m  ✗\033[0m %s\n' "$1" >&2; }

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "'$1' not found on PATH. $2"
    exit 1
  fi
}

# --- Prerequisites -----------------------------------------------------------

info "Checking prerequisites"
require flutter "Install Flutter 3.11+: https://docs.flutter.dev/get-started/install"
require java    "Install a JDK 17+ (e.g. 'brew install --cask temurin@17')."
ok "flutter: $(flutter --version 2>/dev/null | head -1)"
ok "java:    $(java -version 2>&1 | head -1)"

# --- Host tests --------------------------------------------------------------

info "flutter pub get"
flutter pub get

info "flutter analyze"
flutter analyze

info "flutter test (host unit + widget tests)"
flutter test

ok "Host tests passed."

if [ "$RUN_EMULATOR" -eq 0 ]; then
  echo
  echo "Skipped emulator integration test. Re-run with --emulator to include it."
  exit 0
fi

# --- Emulator integration smoke test -----------------------------------------

info "Setting up Android emulator"
require sdkmanager "Install Android cmdline-tools and add them to PATH (ANDROID_SDK_ROOT)."
require avdmanager "Install Android cmdline-tools and add them to PATH (ANDROID_SDK_ROOT)."
require emulator   "Install the Android 'emulator' package via sdkmanager."

# Pick an ABI matching the host CPU (Apple Silicon vs Intel).
case "$(uname -m)" in
  arm64|aarch64) ABI="arm64-v8a" ;;
  *)             ABI="x86_64" ;;
esac
IMAGE="system-images;android-${ANDROID_API};google_apis;${ABI}"

if ! sdkmanager --list_installed 2>/dev/null | grep -q "${IMAGE}"; then
  info "Installing ${IMAGE}"
  yes | sdkmanager "platform-tools" "emulator" "${IMAGE}"
else
  ok "System image already installed: ${IMAGE}"
fi

if ! avdmanager list avd 2>/dev/null | grep -q "Name: ${AVD_NAME}"; then
  info "Creating AVD '${AVD_NAME}'"
  echo "no" | avdmanager create avd -n "${AVD_NAME}" -k "${IMAGE}" -d pixel_6
else
  ok "AVD already exists: ${AVD_NAME}"
fi

info "Booting emulator '${AVD_NAME}'"
emulator -avd "${AVD_NAME}" -no-snapshot -no-boot-anim -netdelay none -netspeed full \
  >/tmp/ajopaivakirja-emulator.log 2>&1 &
EMULATOR_PID=$!
trap 'kill "$EMULATOR_PID" 2>/dev/null || true' EXIT

info "Waiting for device to come online"
adb wait-for-device
# Block until Android finished booting.
until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
  sleep 2
done
ok "Emulator booted."

info "flutter test integration_test/app_smoke_test.dart"
flutter test integration_test/app_smoke_test.dart

ok "Emulator integration smoke test passed."
