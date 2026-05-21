#!/usr/bin/env bash
#
# Build a debug APK, boot a local Android emulator (if needed), and install
# the app on it — an end-to-end deploy loop for manual testing.
#
#   ./scripts/deploy-emulator.sh
#
# If an emulator or device is already attached, it reuses it. Otherwise it
# provisions and boots the 'test_pixel' AVD automatically.
#
# Does NOT install the Flutter or Android SDK; it locates the Android SDK
# and checks for required tools.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

AVD_NAME="test_pixel"
ANDROID_API="34"
APP_ID="fi.lpalokan.kilometrikorvaus"
APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"

info()  { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }
ok()    { printf '\033[1;32m  ✓\033[0m %s\n' "$1"; }
fail()  { printf '\033[1;31m  ✗\033[0m %s\n' "$1" >&2; }

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "'$1' not found on PATH. $2"
    exit 1
  fi
}

# ── Prerequisites ───────────────────────────────────────────────────────────

info "Checking prerequisites"
require flutter "Install Flutter 3.11+: https://docs.flutter.dev/get-started/install"
require java    "Install a JDK 17+ (e.g. 'brew install --cask temurin@17')."

# ── Build debug APK ─────────────────────────────────────────────────────────

info "Building debug APK"
bash scripts/build.sh apk --debug
ok "APK built: $APK_PATH"

# ── Locate & configure Android SDK ──────────────────────────────────────────

SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [ -z "$SDK_ROOT" ]; then
  for cand in "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    [ -d "$cand" ] && SDK_ROOT="$cand" && break
  done
fi
if [ -n "$SDK_ROOT" ] && [ -d "$SDK_ROOT" ]; then
  ok "Android SDK: $SDK_ROOT"
  export ANDROID_SDK_ROOT="$SDK_ROOT"
  for d in emulator platform-tools cmdline-tools/latest/bin tools/bin; do
    [ -d "$SDK_ROOT/$d" ] && PATH="$SDK_ROOT/$d:$PATH"
  done
  export PATH
else
  fail "Android SDK not found. Set ANDROID_SDK_ROOT or install via Android Studio."
  exit 1
fi

require adb "Android platform-tools missing from the SDK."

# ── Boot emulator (if no device is already online) ──────────────────────────

EMULATOR_PID=""
if adb devices | awk 'NR>1 && $2=="device"{found=1} END{exit !found}'; then
  ok "Using already-attached device/emulator."
else
  require emulator    "Install the Android 'emulator' package (Android Studio > SDK Manager)."
  require avdmanager  "Install Android cmdline-tools (Android Studio > SDK Manager)."
  require sdkmanager  "Install Android cmdline-tools (Android Studio > SDK Manager)."

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
  until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
    sleep 2
  done
  ok "Emulator booted."
fi

# ── Install the app ─────────────────────────────────────────────────────────

info "Installing app on emulator"
adb install -r "$APK_PATH"
ok "App installed."

# Grant notification permission (Android 13+) so a permission dialog
# doesn't block the first launch.
adb shell pm grant "$APP_ID" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true

# ── Launch the app ──────────────────────────────────────────────────────────

info "Launching app"
adb shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
ok "App launched. Check the emulator window."

echo
echo "Emulator is running. Press Ctrl-C to stop the emulator when done."
if [ -n "${EMULATOR_PID:-}" ]; then
  wait "$EMULATOR_PID"
fi
