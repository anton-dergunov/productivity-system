#!/usr/bin/env bash
# Run Emacs with this repo as the config directory (no install needed).
# Uses --init-directory (Emacs 29+) so user-emacs-directory points here.
# On first run, packages are downloaded into elpa/ inside this repo.
# local.el in the repo root points org files at samples/realistic/.
#
# Pass --emacs <path> to use a custom Emacs binary (default: EMACS_BIN env var or
# /Applications/Emacs.app). Examples:
#   ./run_emacs_dev.sh --emacs ~/Applications/Emacs-latest
#   EMACS_BIN=/path/to/emacs ./run_emacs_dev.sh
#
# To use Homebrew emacs-plus@30:
#   EMACS_BIN="$(brew --prefix)/opt/emacs-plus@30/Emacs.app/Contents/MacOS/Emacs" ./run_emacs_dev.sh
#
# Pass --sandbox to copy the repo (without .git) to a temp dir under /tmp and
# run from there instead. Useful for testing without risking commits to this
# repo's git history. The temp dir is removed when Emacs exits.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

SANDBOX=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --emacs)
      EMACS_BIN="$2"
      shift 2
      ;;
    --sandbox)
      SANDBOX=true
      shift
      ;;
    *)
      break
      ;;
  esac
done

# If --emacs not provided, check EMACS_BIN env var, else use default
if [[ -z "${EMACS_BIN:-}" ]]; then
  EMACS_BIN="/Applications/Emacs.app/Contents/MacOS/Emacs"
fi

# If a directory path was passed (e.g. ~/Applications/Emacs-latest), append the binary path
if [[ -d "$EMACS_BIN" ]]; then
  EMACS_BIN="$EMACS_BIN/Contents/MacOS/Emacs"
fi

LOCAL_EL="$REPO_DIR/local.el"
if [ ! -f "$LOCAL_EL" ]; then
  echo "Creating $LOCAL_EL pointing to samples/realistic/"
  cat > "$LOCAL_EL" <<'EOF'
(setq my-org-base-directory
      (expand-file-name "samples/realistic/" user-emacs-directory))
EOF
fi

# If --sandbox, copy the repo (without .git) to a temp dir under /tmp and run
# from there instead. elpa/ is symlinked rather than copied so packages don't
# need re-downloading.
if $SANDBOX; then
  SANDBOX_DIR="$(mktemp -d /tmp/emacs-sandbox-XXXXXX)"
  echo "Sandbox: $SANDBOX_DIR (removed on exit; no .git, so auto-sync can't commit here)"
  rsync -a --exclude='.git' --exclude='elpa' "$REPO_DIR/" "$SANDBOX_DIR/"
  [ -d "$REPO_DIR/elpa" ] && ln -s "$REPO_DIR/elpa" "$SANDBOX_DIR/elpa"
  INIT_DIR="$SANDBOX_DIR"
else
  INIT_DIR="$REPO_DIR"
fi

# Belt-and-suspenders: PS_GIT_SYNC_DISABLE (checked in config.org) prevents
# the sync timer from ever starting; ps/git-sync-paused is a runtime fallback.
export PS_GIT_SYNC_DISABLE=1

if $SANDBOX; then
  "$EMACS_BIN" --init-directory "$INIT_DIR" \
    --eval "(setq ps/git-sync-paused t)" \
    "$@"
  rm -rf "$SANDBOX_DIR"
else
  exec "$EMACS_BIN" --init-directory "$INIT_DIR" \
    --eval "(setq ps/git-sync-paused t)" \
    "$@"
fi
