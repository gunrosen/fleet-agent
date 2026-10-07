#!/usr/bin/env bash
# fleet-proc.sh — registry for long-running background processes started by fleet agents
# (dev servers, watchers, `run_in_background` jobs). Registered processes can be listed and
# stopped later, and fleet-down stops them even if the agent that started them has died.
#
# Usage:
#   ./fleet-proc.sh run <label> -- <cmd> [args...]   register, then exec <cmd> (same PID, so
#                                                    the registry points at the real process)
#   ./fleet-proc.sh list                             live registered processes
#   ./fleet-proc.sh stop <label|pid>... | --all      stop their process trees, unregister
#
# Example (agent Bash tool, run in background):
#   fleet-proc run backend -- mvn spring-boot:run > /tmp/backend.log 2>&1
#
# Registry: $FLEET_PROCS (fleet-init sets it per tmux session), else <TARGET_REPO>/fleet/procs.tsv
# from the fleet config. Rows are matched by PID + start time, so a recycled PID is never hit.
#
set -euo pipefail

SELF="${BASH_SOURCE[0]}"
while [[ -L "$SELF" ]]; do t="$(readlink "$SELF")"; [[ "$t" == /* ]] && SELF="$t" || SELF="$(dirname "$SELF")/$t"; done
# shellcheck source=fleet-lib.sh
source "$(cd "$(dirname "$SELF")" && pwd)/fleet-lib.sh"

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

REG="${FLEET_PROCS:-}"
if [[ -z "$REG" ]]; then
  fleet_load_config || { echo "no registry: set FLEET_PROCS or provide a fleet config" >&2; exit 1; }
  REG="$FLEET_REGISTRY"
fi
KILL_GRACE="${KILL_GRACE:-5}"

cmd="${1:-}"; [[ $# -gt 0 ]] && shift
case "$cmd" in
  run)
    label="${1:?usage: fleet-proc run <label> -- <cmd> [args...]}"; shift
    [[ "${1:-}" == "--" ]] && shift
    [[ $# -gt 0 ]] || usage 2
    sess="${FLEET_SESSION:-}"
    if [[ -z "$sess" && -n "${TMUX_PANE:-}" ]]; then
      sess="$(tmux display-message -p -t "$TMUX_PANE" '#S' 2>/dev/null || true)"
    fi
    mkdir -p "$(dirname "$REG")"
    [[ -s "$REG" ]] || printf '#pid\tstarted\tsession\tlabel\tcwd\tcommand\n' > "$REG"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$$" "$(fleet_lstart $$)" "${sess:--}" "$label" "$PWD" \
      "$(echo "$*" | tr '\t\n' '  ')" >> "$REG"
    exec "$@"
    ;;

  list)
    live="$(fleet_reg_live "$REG")"
    [[ -n "$live" ]] || { echo "no live registered processes ($REG)"; exit 0; }
    printf '%-7s %-18s %-14s %-8s %s\n' PID SESSION LABEL UPTIME COMMAND
    while IFS=$'\t' read -r pid _ sess label _ cmdline; do
      printf '%-7s %-18s %-14s %-8s %s\n' "$pid" "$sess" "$label" \
        "$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ' || true)" "${cmdline:0:80}"
    done <<< "$live"
    ;;

  stop)
    [[ $# -gt 0 ]] || usage 2
    pids=""
    while IFS=$'\t' read -r pid _ _ label _; do
      [[ -n "$pid" ]] || continue
      for want in "$@"; do
        if [[ "$want" == "--all" || "$want" == "$label" || "$want" == "$pid" ]]; then
          pids="$pids $pid"; break
        fi
      done
    done <<< "$(fleet_reg_live "$REG")"
    if [[ -z "${pids// /}" ]]; then
      echo "nothing to stop (no live registered process matches: $*)"
      fleet_reg_prune "$REG"
      exit 0
    fi
    # shellcheck disable=SC2086
    n="$(fleet_kill $(fleet_tree $pids))"
    fleet_reg_prune "$REG" "$pids"
    echo "stopped:$pids ($n process(es) incl. children)"
    ;;

  -h|--help|"") usage ;;
  *) echo "unknown command: $cmd" >&2; usage 2 ;;
esac
