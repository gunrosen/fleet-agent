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
}
