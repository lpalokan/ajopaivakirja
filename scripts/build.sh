#!/bin/bash
# Build wrapper — runs version.sh before Flutter to ensure
# app_version.dart is generated before Dart compilation.
#
# Usage: ./scripts/build.sh [--debug] [--release] [any flutter build args...]
#
# Examples:
#   ./scripts/build.sh apk --debug
#   ./scripts/build.sh apk
#   ./scripts/build.sh appbundle --release

set -e

MODE="release"
FLUTTER_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --debug) MODE="debug" ;;
    --release) MODE="release" ;;
    *) FLUTTER_ARGS+=("$arg") ;;
  esac
done

# Generate version file before Flutter compiles
bash scripts/version.sh "--$MODE"

# Run Flutter build
flutter build "${FLUTTER_ARGS[@]}"
