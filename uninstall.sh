#!/usr/bin/env bash
# uninstall.sh — remove Fleet symlinks/copies installed by install.sh.
# Leaves your ~/.config/fleet/fleet.config untouched (delete it manually if wanted).
set -euo pipefail

SKILLS_DST="$HOME/.claude/skills"
BIN_DST="$HOME/.local/bin"

echo "== Fleet uninstall =="
for name in agents-communication fleet-manager fleet-worker; do
  t="$SKILLS_DST/$name"
  [[ -e "$t" || -L "$t" ]] && { rm -rf "$t"; echo "  - removed skill $name"; }
done
for cmd in fleet-init fleet-send fleet-down fleet-status fleet-proc fleet-lib.sh; do
  t="$BIN_DST/$cmd"
  [[ -e "$t" || -L "$t" ]] && { rm -f "$t"; echo "  - removed command $cmd"; }
done
echo "Kept: ~/.config/fleet/fleet.config (remove manually if you want a clean slate)."
