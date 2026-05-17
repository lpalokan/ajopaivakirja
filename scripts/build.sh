#!/bin/bash
# Build wrapper — runs version.sh before Flutter to ensure
# app_version.dart is generated before Dart compilation.
#
# Usage: ./scripts/build.sh <target> [--debug] [--release] [any flutter build args...]
#
# Examples:
#   ./scripts/build.sh apk --debug
#   ./scripts/build.sh apk
#   ./scripts/build.sh appbundle --release

set -e

# Ensure we run from the project root (where pubspec.yaml lives)
cd "$(dirname "$0")/.."

usage() {
  cat <<'EOF'
Usage: ./scripts/build.sh <target> [--debug] [--release] [flutter build args...]

<target> is the Flutter build target, e.g. apk, appbundle, aar.

Examples:
  ./scripts/build.sh apk --debug
  ./scripts/build.sh apk
  ./scripts/build.sh appbundle --release
EOF
}

MODE="release"
FLUTTER_ARGS=()
HAS_TARGET=0

for arg in "$@"; do
  case "$arg" in
    --debug) MODE="debug" ; FLUTTER_ARGS+=("$arg") ;;
    --release) MODE="release" ; FLUTTER_ARGS+=("$arg") ;;
    --*) FLUTTER_ARGS+=("$arg") ;;
    *) HAS_TARGET=1 ; FLUTTER_ARGS+=("$arg") ;;
  esac
done

if [ "$HAS_TARGET" -eq 0 ]; then
  echo "error: no Flutter build target given (e.g. apk, appbundle)." >&2
  echo >&2
  usage >&2
  exit 1
fi

# Generate version file before Flutter compiles
echo "==> Running version.sh --$MODE"
bash scripts/version.sh "--$MODE"

# Run Flutter build
echo "==> Running flutter build ${FLUTTER_ARGS[*]}"
flutter build "${FLUTTER_ARGS[@]}"
