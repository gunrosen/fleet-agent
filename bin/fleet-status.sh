#!/usr/bin/env bash
# fleet-status.sh — show what the fleet is still running and what it costs.
#
# Closing a terminal tab only DETACHES tmux: agents, their MCP servers and any background
# jobs keep running (and can keep burning CPU, memory and tokens). This lists, per session:
# attached clients, idle time, process count, CPU% and RSS of the whole process tree; then
# processes registered via `fleet-proc run`, and orphans left inside the worktrees.
#
# Usage:
#   ./fleet-status.sh [--config path]
#
set -euo pipefail

SELF="${BASH_SOURCE[0]}"
while [[ -L "$SELF" ]]; do t="$(readlink "$SELF")"; [[ "$t" == /* ]] && SELF="$t" || SELF="$(dirname "$SELF")/$t"; done
# shellcheck source=fleet-lib.sh
source "$(cd "$(dirname "$SELF")" && pwd)/fleet-lib.sh"

CONFIG_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)  CONFIG_FILE="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

fleet_load_config "$CONFIG_FILE" || { echo "no config found (see fleet-init --help)" >&2; exit 1; }

now="$(date +%s)"
fmt='%-22s %-8s %-7s %-6s %-7s %-8s %s\n'

echo "== Fleet status == (prefix '${SESSION_PREFIX:-<none>}', config $FLEET_CONFIG_FILE)"
printf "$fmt" SESSION ATTACHED IDLE PROCS CPU% 'RSS(MB)' PANE
total_cpu=0; total_mb=0; running=0
for s in $(fleet_sessions); do
  if ! tmux has-session -t "=$s" 2>/dev/null; then
    printf "$fmt" "$s" - - - - - "(not running)"
    continue
  fi
  running=$((running + 1))
  attached="$(tmux display-message -p -t "=$s:" '#{session_attached}')"  # pane target: exact session needs the trailing ':'
  # last pane output in any window (session_activity only tracks client input: 0 if never attached)
  activity="$(tmux list-windows -t "=$s" -F '#{window_activity}' | sort -n | tail -1)"
  # shellcheck disable=SC2046
  tree="$(fleet_tree $(tmux list-panes -s -t "=$s" -F '#{pane_pid}') | tr '\n' ' ')"
  # shellcheck disable=SC2086
  read -r cpu mb <<< "$(fleet_usage $tree)"
  procs="$(echo $tree | wc -w | tr -d ' ')"
  pane="$(tmux list-panes -s -t "=$s" -F '#{pane_current_command}' | paste -sd, -)"
  [[ "$attached" -gt 0 ]] && att="yes" || att="no"
  printf "$fmt" "$s" "$att" "$(fleet_dur $((now - activity)))" "$procs" "$cpu" "$mb" "$pane"
  total_cpu="$(awk -v a="$total_cpu" -v b="$cpu" 'BEGIN { printf "%.1f", a + b }')"
  total_mb=$((total_mb + mb))
done
printf "$fmt" TOTAL "" "" "" "$total_cpu" "$total_mb" ""

echo
echo "-- background processes registered via fleet-proc ($FLEET_REGISTRY)"
live="$(fleet_reg_live "$FLEET_REGISTRY")"
if [[ -z "$live" ]]; then
  echo "  none"
else
  printf '  %-7s %-18s %-14s %-8s %-6s %-7s %s\n' PID SESSION LABEL UPTIME CPU% 'RSS(MB)' COMMAND
  while IFS=$'\t' read -r pid _ sess label _ cmd; do
    # shellcheck disable=SC2046
    read -r cpu mb <<< "$(fleet_usage $(fleet_tree "$pid"))"
    up="$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
    printf '  %-7s %-18s %-14s %-8s %-6s %-7s %s\n' "$pid" "$sess" "$label" "$up" "$cpu" "$mb" "${cmd:0:60}"
  done <<< "$live"
fi

echo
echo "-- orphans (ppid 1) with cwd inside $WORKTREE_ROOT"
orphans="$(fleet_orphans_in "$WORKTREE_ROOT" | tr '\n' ',')"
if [[ -z "$orphans" ]]; then
  echo "  none"
else
  ps -o pid=,etime=,rss=,command= -p "${orphans%,}" \
    | awk '{ printf "  %6s %10s %6dMB  %s\n", $1, $2, $3 / 1024, substr($0, index($0, $4), 100) }'
fi

if [[ "$running" -gt 0 || -n "$live" || -n "$orphans" ]]; then
  echo
  echo "Stop everything: fleet-down   (preview with: fleet-down --dry-run)"
fi
