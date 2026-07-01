#!/usr/bin/env bash
# fleet-down.sh — kill fleet tmux sessions and (optionally) remove worktrees.
#
# Usage:
#   ./fleet-down.sh              # kill sessions, keep worktrees + branches
#   ./fleet-down.sh --wipe       # also remove worktrees (branches are kept)
#   ./fleet-down.sh --config path
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${FLEET_CONFIG:-}"
WIPE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wipe)   WIPE=1; shift ;;
    --config) CONFIG_FILE="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$CONFIG_FILE" ]]; then
  for c in "./fleet.config" "$HOME/.config/fleet/fleet.config"; do
    [[ -f "$c" ]] && { CONFIG_FILE="$c"; break; }
  done
fi
[[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]] || { echo "no config found (see fleet-init --help)" >&2; exit 1; }
# shellcheck disable=SC1090
source "$CONFIG_FILE"
SESSION_PREFIX="${SESSION_PREFIX:-}"

kill_sess() {
  local s="$1"
  if tmux has-session -t "$s" 2>/dev/null; then
    tmux kill-session -t "$s"; echo "  - killed session $s"
  fi
}

echo "== Fleet down == (prefix '${SESSION_PREFIX:-<none>}')"
kill_sess "${SESSION_PREFIX}mgr"
for spec in "${WORKERS[@]}"; do
  IFS=: read -r name _ _ <<< "$spec"
  kill_sess "${SESSION_PREFIX}${name}"
done

if [[ "$WIPE" -eq 1 ]]; then
  for spec in "${WORKERS[@]}"; do
    IFS=: read -r name _ _ <<< "$spec"
    wt="$WORKTREE_ROOT/$name"
    if [[ -d "$wt" ]]; then
      git -C "$TARGET_REPO" worktree remove --force "$wt" 2>/dev/null \
        && echo "  - removed worktree $wt" \
        || echo "  ! could not remove worktree $wt (remove manually)"
    fi
  done
  echo "Branches fleet/* are kept. Delete with: git -C \"$TARGET_REPO\" branch -D fleet/<name>"
fi

echo "done."
