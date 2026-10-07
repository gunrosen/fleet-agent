# fleet-lib.sh — shared helpers for the fleet-* scripts. Sourced, never executed.
# Must stay bash 3.2 compatible (macOS /bin/bash): no associative arrays, no mapfile.

# Resolve and source the fleet config, then fill derived defaults.
# Order (first hit wins): $1 (--config) > $FLEET_CONFIG > ./fleet.config > ~/.config/fleet/fleet.config
# Returns 1 if no config is found. Sets FLEET_CONFIG_FILE.
fleet_load_config() {
  local cfg="${1:-${FLEET_CONFIG:-}}" c
  if [[ -z "$cfg" ]]; then
    for c in "./fleet.config" "$HOME/.config/fleet/fleet.config"; do
      [[ -f "$c" ]] && { cfg="$c"; break; }
    done
  fi
  [[ -n "$cfg" && -f "$cfg" ]] || return 1
  FLEET_CONFIG_FILE="$cfg"
  # shellcheck disable=SC1090
  source "$cfg"
  SESSION_PREFIX="${SESSION_PREFIX:-}"
  KILL_GRACE="${KILL_GRACE:-5}"
}

# Print every fleet tmux session name for the loaded config (manager first).
fleet_sessions() {
  local spec name
  echo "${SESSION_PREFIX}mgr"
  for spec in "${WORKERS[@]}"; do
    IFS=: read -r name _ _ <<< "$spec"
    echo "${SESSION_PREFIX}${name}"
  done
}

# Print the given PIDs plus all of their descendants, from one snapshot of the process table.
# Must be called while the parents are still alive: once a parent dies its children are
# re-parented to launchd (ppid 1) and can no longer be traced back.
fleet_tree() {
  [[ $# -gt 0 ]] || return 0
  ps -axo pid=,ppid= | awk -v roots="$*" '
    BEGIN { n = split(roots, r, " "); for (i = 1; i <= n; i++) keep[r[i]] = 1 }
    { par[$1] = $2 }
    END {
      do {
        grew = 0
        for (p in par) if (!(p in keep) && (par[p] in keep)) { keep[p] = 1; grew = 1 }
      } while (grew)
      for (p in keep) if (p in par) print p
    }'
}

# PIDs of this script and all its ancestors — never signal these (e.g. when the manager
# agent itself runs fleet-down from inside its pane).
fleet_self_chain() {
  ps -axo pid=,ppid= | awk -v me="$$" '
    { par[$1] = $2 }
    END { p = me; while (p > 1 && (p in par)) { print p; p = par[p] } }'
}

# Print the subset of the given PIDs that are still running (zombies excluded).
fleet_alive() {
  [[ $# -gt 0 ]] || return 0
  { ps -o pid=,stat= -p "$(echo "$*" | tr ' ' ',')" 2>/dev/null || true; } | awk '$2 !~ /^Z/ { print $1 }'
}

# SIGTERM the PIDs, wait up to $KILL_GRACE seconds, then SIGKILL whatever survived.
# Skips this script's own ancestry. Prints the number of processes signalled.
fleet_kill() {
  local skip p i targets=() left
  skip=" $(fleet_self_chain | tr '\n' ' ') "
  for p in "$@"; do
    [[ "$skip" == *" $p "* ]] || targets+=("$p")
  done
  if [[ ${#targets[@]} -eq 0 ]]; then echo 0; return 0; fi
  kill -TERM "${targets[@]}" 2>/dev/null || true
  for ((i = 0; i < KILL_GRACE * 10; i++)); do
    left="$(fleet_alive "${targets[@]}")"
    [[ -z "$left" ]] && break
    sleep 0.1
  done
  left="$(fleet_alive "${targets[@]}")"
  if [[ -n "$left" ]]; then
    # shellcheck disable=SC2086
    kill -KILL $left 2>/dev/null || true
    # SIGKILL is delivered asynchronously; wait so callers see them gone.
    for ((i = 0; i < 20; i++)); do
      [[ -z "$(fleet_alive "${targets[@]}")" ]] && break
      sleep 0.1
    done
  fi
  echo "${#targets[@]}"
}

# PIDs re-parented to launchd (ppid 1) whose cwd is inside directory $1 — leftovers of an
# agent that died without cleaning up. tmux servers are excluded.
fleet_orphans_in() {
  local root
  root="$(cd "$1" 2>/dev/null && pwd -P)" || return 0
  { ps -axo pid=,ppid=,comm=; echo "--"; lsof -a -u "$(id -u)" -d cwd -Fpn 2>/dev/null || true; } | awk -v root="$root" '
    $0 == "--" { cwdsec = 1; next }
    !cwdsec { ppid[$1] = $2; comm[$1] = $3; next }
    /^p/ { pid = substr($0, 2); next }
    /^n/ {
      dir = substr($0, 2)
      if ((dir == root || index(dir, root "/") == 1) && ppid[pid] == 1 && comm[pid] !~ /(^|\/)tmux$/) print pid
    }'
}

# Sum %CPU and RSS (MB) over the given PIDs: prints "<cpu> <mb>".
fleet_usage() {
  if [[ $# -eq 0 ]]; then echo "0.0 0"; return 0; fi
  { ps -o pcpu=,rss= -p "$(echo "$*" | tr ' ' ',')" 2>/dev/null || true; } \
    | awk '{ c += $1; r += $2 } END { printf "%.1f %d\n", c, r / 1024 }'
}

# Seconds -> compact duration, e.g. 7380 -> 2h03m.
fleet_dur() {
  local s="$1"
  if   (( s >= 86400 )); then printf '%dd%02dh' $((s / 86400)) $((s % 86400 / 3600))
  elif (( s >= 3600 ));  then printf '%dh%02dm' $((s / 3600)) $((s % 3600 / 60))
  elif (( s >= 60 ));    then printf '%dm' $((s / 60))
  else printf '%ds' "$s"
  fi
}
