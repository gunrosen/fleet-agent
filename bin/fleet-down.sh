#!/usr/bin/env bash
# fleet-down.sh — stop the fleet: kill its tmux sessions AND every process the agents left
# behind, then (optionally) remove worktrees.
#
# Killing a tmux session only HUPs the pane's process group. Background shells an agent
# started (dev servers, mvn, grunt, watchers) run in their own sessions, never get that
# signal, and would be orphaned to launchd. So the whole tree is collected first:
#   * every descendant of each session's pane (agent + MCP servers + background shells)
#   * orphans (ppid 1) whose cwd is inside WORKTREE_ROOT
# then SIGTERM, wait KILL_GRACE seconds, SIGKILL survivors.
#
# Usage:
#   ./fleet-down.sh              # stop sessions + processes, keep worktrees + branches
#   ./fleet-down.sh --dry-run    # only list what would be stopped
#   ./fleet-down.sh --wipe       # also remove worktrees (branches are kept)
#   ./fleet-down.sh --config path
#
set -euo pipefail

SELF="${BASH_SOURCE[0]}"
while [[ -L "$SELF" ]]; do t="$(readlink "$SELF")"; [[ "$t" == /* ]] && SELF="$t" || SELF="$(dirname "$SELF")/$t"; done
# shellcheck source=fleet-lib.sh
source "$(cd "$(dirname "$SELF")" && pwd)/fleet-lib.sh"

CONFIG_FILE=""
WIPE=0
DRY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wipe)    WIPE=1; shift ;;
    --dry-run) DRY=1; shift ;;
    --config)  CONFIG_FILE="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

fleet_load_config "$CONFIG_FILE" || { echo "no config found (see fleet-init --help)" >&2; exit 1; }

echo "== Fleet down == (prefix '${SESSION_PREFIX:-<none>}')"

# --- 1) collect, while parents are still alive --------------------------------
sessions=()
roots=()
for s in $(fleet_sessions); do
  tmux has-session -t "=$s" 2>/dev/null || continue
  sessions+=("$s")
  roots+=($(tmux list-panes -s -t "=$s" -F '#{pane_pid}'))
done
victims="$(fleet_tree ${roots[@]+"${roots[@]}"} | tr '\n' ' ')"

if [[ "$DRY" -eq 1 ]]; then
  orphans="$(fleet_orphans_in "$WORKTREE_ROOT" | tr '\n' ' ')"
  echo "sessions : ${sessions[*]+"${sessions[*]}"}"
  all="$(echo $victims $orphans | tr ' ' '\n' | sort -un | tr '\n' ' ')"
  if [[ -n "${all// /}" ]]; then
    echo "processes that would be stopped:"
    ps -o pid=,rss=,command= -p "$(echo $all | tr ' ' ',')" \
      | awk '{ printf "  %6s %6dMB  %s\n", $1, $2 / 1024, substr($0, index($0, $3), 120) }'
  else
    echo "no processes to stop"
  fi
  exit 0
fi

# --- 2) close sessions (agents get SIGHUP and a chance to exit cleanly) -------
for s in ${sessions[@]+"${sessions[@]}"}; do
  tmux kill-session -t "=$s" && echo "  - killed session $s"
done

# --- 3) stop whatever is still running ----------------------------------------
orphans="$(fleet_orphans_in "$WORKTREE_ROOT" | tr '\n' ' ')"
# shellcheck disable=SC2086
left="$(fleet_alive $victims $orphans | sort -un | tr '\n' ' ')"
if [[ -n "${left// /}" ]]; then
  # shellcheck disable=SC2086
  n="$(fleet_kill $left)"
  echo "  - stopped $n leftover process(es) (agents, MCP servers, background jobs)"
fi

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
