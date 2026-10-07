#!/usr/bin/env bash
# install.sh — install the Fleet toolkit (Model B: launcher-centric).
#   * skills  -> ~/.claude/skills/         (global, loaded by every claude session)
#   * scripts -> ~/.local/bin/             (fleet-init, fleet-send, fleet-down, fleet-status,
#                                           fleet-proc on PATH, + fleet-lib.sh they source)
#   * config  -> ~/.config/fleet/fleet.config  (from the example, if absent)
#
# By default it SYMLINKS, so `git pull` in this repo auto-updates your install.
# Pass --copy to install detached copies instead.
#
# Usage: ./install.sh [--copy]
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="link"
[[ "${1:-}" == "--copy" ]] && MODE="copy"

SKILLS_DST="$HOME/.claude/skills"
BIN_DST="$HOME/.local/bin"
CFG_DIR="$HOME/.config/fleet"
CFG_DST="$CFG_DIR/fleet.config"

link_or_copy() {  # $1 src  $2 dst
  local src="$1" dst="$2"
  if [[ "$MODE" == "link" && -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    return 0  # already linked to this repo
  fi
  if [[ -e "$dst" || -L "$dst" ]]; then
    local bak="$dst.bak.$$"
    mv "$dst" "$bak"; echo "    backed up existing -> $bak"
  fi
  if [[ "$MODE" == "link" ]]; then ln -s "$src" "$dst"; else cp -R "$src" "$dst"; fi
}

echo "== Fleet install ($MODE) from $REPO =="

# --- deps (warn only; claude/tmux/git are needed at run time) ----------------
for dep in tmux git claude; do
  command -v "$dep" >/dev/null || echo "  ! WARNING: '$dep' not found on PATH — needed to run the fleet"
done

# --- skills -> ~/.claude/skills ----------------------------------------------
echo "-- skills -> $SKILLS_DST"
mkdir -p "$SKILLS_DST"
for d in "$REPO"/skills/*/; do
  name="$(basename "$d")"
  link_or_copy "${d%/}" "$SKILLS_DST/$name"
  echo "  + $name"
done

# --- scripts -> ~/.local/bin (strip .sh for clean command names) -------------
echo "-- scripts -> $BIN_DST"
mkdir -p "$BIN_DST"
for s in "$REPO"/bin/fleet-{init,send,down,status,proc}.sh; do
  chmod +x "$s"
  cmd="$(basename "$s" .sh)"
  link_or_copy "$s" "$BIN_DST/$cmd"
  echo "  + $cmd"
done
# shared helpers, sourced (not executed) by the commands above; kept next to them for --copy
link_or_copy "$REPO/bin/fleet-lib.sh" "$BIN_DST/fleet-lib.sh"
echo "  + fleet-lib.sh"

# --- config -> ~/.config/fleet/fleet.config (never overwrite) ----------------
echo "-- config -> $CFG_DST"
mkdir -p "$CFG_DIR"
if [[ -f "$CFG_DST" ]]; then
  echo "  ~ exists, kept as-is"
else
  cp "$REPO/bin/fleet.config.example" "$CFG_DST"
  echo "  + created from example — EDIT THIS before running (TARGET_REPO, WORKERS)"
fi

# --- PATH check --------------------------------------------------------------
case ":$PATH:" in
  *":$BIN_DST:"*) : ;;
  *) echo
     echo "  ! $BIN_DST is not on your PATH. Add to your shell rc:"
     echo "      export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

echo
echo "Done. Next:"
echo "  1) edit  $CFG_DST   (set TARGET_REPO to your project, tune WORKERS)"
echo "  2) run   fleet-init                  (from anywhere)"
echo "  3) task  fleet-send mgr \"<feature request>\""
echo "  4) check fleet-status              (closing the terminal does NOT stop agents)"
echo "  5) stop  fleet-down --wipe"
