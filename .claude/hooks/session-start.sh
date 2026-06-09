#!/bin/bash
# SessionStart hook: make `flutter` and the test toolchain available in
# Claude Code on the web (ephemeral containers start without Flutter).
# No-op on local machines, where Flutter is already installed.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# libsqlite3 backs sqflite_common_ffi for the headless integration suite
# (scripts/host-bdd.sh). Ships with Ubuntu; install best-effort if missing.
if ! ldconfig -p 2>/dev/null | grep -q libsqlite3; then
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y libsqlite3-0 >/dev/null 2>&1 || true
fi

# Installs a pinned Flutter SDK (idempotent) and runs `flutter pub get`.
bash "$CLAUDE_PROJECT_DIR/scripts/setup-test-env.sh"

# Persist flutter on PATH for this session's tool shells.
if [ -x /opt/flutter/bin/flutter ]; then
  echo 'export PATH="/opt/flutter/bin:$PATH"' >> "$CLAUDE_ENV_FILE"
elif [ -x "$HOME/flutter/bin/flutter" ]; then
  echo "export PATH=\"$HOME/flutter/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi
