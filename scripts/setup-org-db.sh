#!/usr/bin/env bash
# Vendor org-db-v3 (https://github.com/jkitchin/org-db-v3) into elpa/org-db-v3
# and set up its Python/FastAPI server, so lisp/ps-org-db.el can use its
# indexing client, server lifecycle, and parser without the transient-based
# UI (avoids the transient version-skew issue).
#
# elpa/ is gitignored and managed like the existing claude-code-ide checkout --
# this is a one-time local setup step, not something committed to the repo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
TARGET="$REPO_DIR/elpa/org-db-v3"

if [ -d "$TARGET" ]; then
  echo "org-db-v3 already present at $TARGET"
else
  echo "Cloning org-db-v3 into $TARGET..."
  git clone https://github.com/jkitchin/org-db-v3 "$TARGET"
fi

echo "Setting up the org-db-v3 Python server (uv sync)..."
(cd "$TARGET/python" && uv sync)

echo "Done. The server will be started automatically by Emacs (ps/org-db-enable)."
