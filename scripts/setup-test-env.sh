#!/usr/bin/env bash
# Idempotent setup for running this project's analyzer and tests in an
# ephemeral environment (e.g. a Claude Code web session) where Flutter is not
# preinstalled. Safe to re-run: it skips work that is already done.
#
#   bash scripts/setup-test-env.sh
#
# After it runs, `flutter` is on PATH for NEW shells (it writes a profile.d
# entry). In the current shell, either open a new shell or run:
#   export PATH="$FLUTTER_HOME/bin:$PATH"
#
# What it does:
#   1. Downloads a pinned Flutter stable SDK (matches pubspec `sdk: ^3.11.5`).
#   2. Puts flutter on PATH for future shells.
#   3. Marks the SDK + repo as git "safe.directory" (needed when running as root).
#   4. Runs `flutter pub get`.
#
# The headless integration suite additionally needs libsqlite3 (for
# sqflite_common_ffi); it ships with Ubuntu. See scripts/host-bdd.sh.
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.1}"
FLUTTER_HOME="${FLUTTER_HOME:-/opt/flutter}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ARCH="$(uname -m)"
if [ "$ARCH" != "x86_64" ]; then
  echo "WARNING: this script downloads the x86_64 Linux SDK; arch is $ARCH." >&2
fi

# 0. If Flutter is already usable (local dev machine), just resolve deps.
if command -v flutter >/dev/null 2>&1; then
  echo "==> Flutter already on PATH: $(command -v flutter)"
  git config --global --add safe.directory "$REPO_DIR" || true
  ( cd "$REPO_DIR" && flutter pub get )
  echo "==> Done (used existing Flutter)."
  exit 0
fi

# 1. Install the SDK if missing.
if [ ! -x "$FLUTTER_HOME/bin/flutter" ]; then
  if [ ! -w "$(dirname "$FLUTTER_HOME")" ]; then
    FLUTTER_HOME="$HOME/flutter"
    echo "==> /opt not writable; installing to $FLUTTER_HOME instead"
  fi
  echo "==> Downloading Flutter $FLUTTER_VERSION to $FLUTTER_HOME"
  tarball="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${tarball}"
  tmp="$(mktemp -d)"
  curl -fsSL --retry 4 --retry-delay 2 -o "$tmp/$tarball" "$url"
  mkdir -p "$(dirname "$FLUTTER_HOME")"
  tar -xf "$tmp/$tarball" -C "$(dirname "$FLUTTER_HOME")"
  rm -rf "$tmp"
else
  echo "==> Flutter already present at $FLUTTER_HOME"
fi

export PATH="$FLUTTER_HOME/bin:$PATH"

# 2. Persist PATH for future shells.
profile_line="export PATH=\"$FLUTTER_HOME/bin:\$PATH\""
if [ -w /etc/profile.d ] 2>/dev/null; then
  echo "$profile_line" > /etc/profile.d/flutter.sh
fi
for rc in "$HOME/.bashrc" "$HOME/.profile"; do
  [ -f "$rc" ] || touch "$rc"
  grep -qF "$FLUTTER_HOME/bin" "$rc" || echo "$profile_line" >> "$rc"
done

# 3. git safe.directory (flutter shells out to git inside its own checkout;
#    running as root in a fresh container otherwise hits "dubious ownership").
git config --global --add safe.directory "$FLUTTER_HOME" || true
git config --global --add safe.directory "$REPO_DIR" || true

# 4. Resolve dependencies.
echo "==> flutter pub get"
( cd "$REPO_DIR" && flutter pub get )

echo
echo "==> Done. Flutter $(flutter --version | head -1)"
echo "    Open a new shell, or: export PATH=\"$FLUTTER_HOME/bin:\$PATH\""
