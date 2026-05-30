#!/usr/bin/env bash
#
# Fast integration-test iteration runner.
#
# Unlike scripts/integration-report.sh (the canonical, full report that records
# video and publishes artifacts), this script is built for the inner loop:
# it installs the app ONCE and lets you run just the scenarios you care about,
# so a single failing case doesn't cost a full 78-scenario run.
#
#   ./scripts/itest.sh                       Run every scenario (one install)
#   ./scripts/itest.sh "Two legs accumulate" Run scenarios whose name contains
#                                             this text (--plain-name)
#   ./scripts/itest.sh -k '2026|grand total' Run scenarios matching this regex
#                                             (--name)
#   ./scripts/itest.sh -f driving            Run only the driving.feature target
#   ./scripts/itest.sh --failed              Re-run ONLY the scenarios that
#                                             failed on the previous run
#   ./scripts/itest.sh --no-gen "..."        Skip build_runner (no .feature
#                                             changes since the last run)
#
# Assumes a device/emulator is already attached (it will not boot one — that is
# the slow path; use integration-report.sh or launch an emulator yourself).
# After every run it records the failing scenario names to
# reports/last-failures.txt so `--failed` can target them next time.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

AGG="integration_test/all_features_test.dart"
REPORT_DIR="$REPO_ROOT/reports"
JSON="$REPORT_DIR/last-run.json"
FAIL_TXT="$REPORT_DIR/last-failures.txt"
FAIL_RE="$REPORT_DIR/last-failures.regex"
APP_ID="fi.lpalokan.kilometrikorvaus"
mkdir -p "$REPORT_DIR"

info() { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$1"; }
fail() { printf '\033[1;31m  ✗\033[0m %s\n' "$1" >&2; }

usage() { sed -n '3,28p' "$0" | sed 's/^# \{0,1\}//'; }

GEN=1
TARGET="$AGG"
FILTER=()

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --no-gen) GEN=0; shift ;;
    --failed)
      if [ ! -s "$FAIL_RE" ]; then
        fail "No recorded failures in $FAIL_RE. Run the suite first."
        exit 1
      fi
      FILTER=(--name "$(cat "$FAIL_RE")")
      info "Re-running previously failed scenarios:"
      sed 's/^/    - /' "$FAIL_TXT"
      shift ;;
    -k|--name)      FILTER=(--name "${2:?regex required}"); shift 2 ;;
    -n|--plain-name) FILTER=(--plain-name "${2:?substring required}"); shift 2 ;;
    -f|--feature)
      TARGET="integration_test/features/${2:?feature name required}_test.dart"
      shift 2 ;;
    --) shift; break ;;
    -*) fail "unknown option: $1"; usage; exit 2 ;;
    *) FILTER=(--plain-name "$1"); shift ;;
  esac
done

# Locate the Android SDK so adb is on PATH (mirrors integration-report.sh).
SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [ -z "$SDK_ROOT" ]; then
  for cand in "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    [ -d "$cand" ] && SDK_ROOT="$cand" && break
  done
fi
if [ -n "$SDK_ROOT" ] && [ -d "$SDK_ROOT" ]; then
  export ANDROID_SDK_ROOT="$SDK_ROOT"
  for d in emulator platform-tools cmdline-tools/latest/bin tools/bin; do
    [ -d "$SDK_ROOT/$d" ] && PATH="$SDK_ROOT/$d:$PATH"
  done
  export PATH
fi

if ! command -v adb >/dev/null 2>&1; then
  fail "adb not found. Set ANDROID_SDK_ROOT."; exit 1
fi
if ! adb devices | awk 'NR>1 && $2=="device"{f=1} END{exit !f}'; then
  fail "No device/emulator attached."
  echo "  Launch one first, e.g.:  flutter emulators --launch test_pixel" >&2
  echo "  (or use scripts/integration-report.sh, which boots one for you)." >&2
  exit 1
fi
ok "Using attached device: $(adb devices | awk 'NR>1 && $2=="device"{print $1; exit}')"

if [ "$GEN" -eq 1 ]; then
  info "Generating Gherkin → Dart (build_runner)"
  dart run build_runner build --delete-conflicting-outputs 2>&1 | tail -3
fi

# Grant POST_NOTIFICATIONS as soon as the app installs so the Android 13+
# permission dialog never blocks the run.
(
  for _ in $(seq 1 120); do
    if adb shell pm list packages 2>/dev/null | grep -q "$APP_ID"; then
      adb shell pm grant "$APP_ID" android.permission.POST_NOTIFICATIONS \
        >/dev/null 2>&1 || true
      break
    fi
    sleep 1
  done
) &
GRANT_PID=$!

if [ "${#FILTER[@]}" -gt 0 ]; then
  info "Running ${TARGET##*/} (filtered: ${FILTER[*]})"
else
  info "Running ${TARGET##*/} (all scenarios)"
fi

# ${FILTER[@]+...} keeps this safe under `set -u` when FILTER is empty
# (macOS ships bash 3.2, which errors on a bare empty-array expansion).
flutter test "$TARGET" ${FILTER[@]+"${FILTER[@]}"} \
  --reporter expanded --file-reporter "json:$JSON" 2>&1
RESULT=${PIPESTATUS[0]}

kill "$GRANT_PID" 2>/dev/null || true

# Record which scenarios failed so `--failed` can target them next time.
dart run scripts/parse_test_failures.dart "$JSON" "$FAIL_TXT" "$FAIL_RE" || true

echo
if [ "$RESULT" -eq 0 ]; then
  ok "PASS"
else
  fail "FAIL (exit $RESULT)"
  if [ -s "$FAIL_TXT" ]; then
    echo "  Re-run just these with:  ./scripts/itest.sh --failed" >&2
  fi
fi
exit "$RESULT"
