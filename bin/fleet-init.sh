#!/usr/bin/env bash
# fleet-init.sh — stand up a tmux fleet: 1 manager (Opus) + N workers, each in its own
# git worktree/branch. Config is read from fleet.config (override via env or --config).
#
# Usage:
#   ./fleet-init.sh [--config path] [--target repo] [--workers N]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Config resolution order (first hit wins):
#   --config <path>  >  $FLEET_CONFIG  >  ./fleet.config  >  ~/.config/fleet/fleet.config
CONFIG_FILE="${FLEET_CONFIG:-}"

# --- arg parsing (all optional; config supplies defaults) --------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)  CONFIG_FILE="$2"; shift 2 ;;
    --target)  TARGET_REPO="$2";  shift 2 ;;
    --base)    BASE_BRANCH="$2";  shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$CONFIG_FILE" ]]; then
  for c in "./fleet.config" "$HOME/.config/fleet/fleet.config"; do
    [[ -f "$c" ]] && { CONFIG_FILE="$c"; break; }
  done
fi
[[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]] || {
  echo "no config found. Create one from the example:" >&2
  echo "  mkdir -p ~/.config/fleet && cp \"$SCRIPT_DIR/fleet.config.example\" ~/.config/fleet/fleet.config" >&2
  echo "or pass --config <path> / set FLEET_CONFIG / run from a dir containing fleet.config" >&2
  exit 1; }
echo "using config: $CONFIG_FILE"
# shellcheck disable=SC1090
source "$CONFIG_FILE"

# --- preflight ---------------------------------------------------------------
command -v tmux  >/dev/null || { echo "tmux not found" >&2; exit 1; }
command -v git   >/dev/null || { echo "git not found"  >&2; exit 1; }
command -v claude>/dev/null || { echo "claude CLI not found" >&2; exit 1; }

if [[ ! -d "$TARGET_REPO/.git" ]]; then
  echo "TARGET_REPO is not a git repo: $TARGET_REPO" >&2
  echo "Create/point it first (e.g. git init), then re-run." >&2
  exit 1
fi

git -C "$TARGET_REPO" rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1 || {
  echo "base branch '$BASE_BRANCH' not found in $TARGET_REPO" >&2; exit 1; }

# Namespace for tmux session names so multiple projects can run in parallel.
# Empty = plain names (mgr, worker-1). Set e.g. SESSION_PREFIX="A-" -> A-mgr, A-worker-1.
SESSION_PREFIX="${SESSION_PREFIX:-}"

mkdir -p "$WORKTREE_ROOT"
mkdir -p "$TARGET_REPO/fleet"
ROSTER="$TARGET_REPO/fleet/roster.tsv"
: > "$ROSTER"
# `session` is the exact tmux target (prefix included); `name` is the bare worker id.
printf 'name\tmodel\trole\tsession\tworktree_path\tbranch\n' >> "$ROSTER"

echo "== Fleet init =="
echo "target repo : $TARGET_REPO (base=$BASE_BRANCH)"
echo "worktrees   : $WORKTREE_ROOT"
echo "manager     : $MANAGER_MODEL"
echo "prefix      : '${SESSION_PREFIX:-<none>}'"

# --- launch helper: start claude inside a fresh tmux session -----------------
# $1 session name, $2 workdir, $3 model, $4 identity system-prompt
# Identity is written to a file and passed via --append-system-prompt-file so the
# text (which contains quotes) never has to survive shell re-quoting.
launch() {
  local sess="$1" dir="$2" model="$3" ident="$4"
  if tmux has-session -t "$sess" 2>/dev/null; then
    echo "  ! session '$sess' already exists — skipping (run fleet-down.sh first)"; return
  fi
  local identf="$TARGET_REPO/fleet/ident-$sess.txt"
  printf '%s\n' "$ident" > "$identf"
  # -c sets pane cwd; run claude as the pane command so send-keys talks to the agent.
  tmux new-session -d -s "$sess" -c "$dir" \
    "claude --model $model $CLAUDE_FLAGS --append-system-prompt-file '$identf'"
  echo "  + tmux session '$sess' ($model) in $dir"
}

# --- workers -----------------------------------------------------------------
for spec in "${WORKERS[@]}"; do
  IFS=: read -r name model role <<< "$spec"
  branch="fleet/${name}"
  wt="$WORKTREE_ROOT/$name"
  sess="${SESSION_PREFIX}${name}"

  if [[ -d "$wt" ]]; then
    echo "  ~ worktree exists: $wt (reusing)"
  else
    git -C "$TARGET_REPO" worktree add -b "$branch" "$wt" "$BASE_BRANCH" >/dev/null
    echo "  + worktree $wt on branch $branch"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$model" "$role" "$sess" "$wt" "$branch" >> "$ROSTER"

  ident="You are Fleet worker '$name' (role=$role), tmux session '$sess'. Your worktree is '$wt' on branch '$branch'. Follow the fleet-worker skill: work only here, commit to this branch, and end each task with the ===WORKER_DONE...=== marker."
  launch "$sess" "$wt" "$model" "$ident"
done

# --- manager -----------------------------------------------------------------
mgr_sess="${SESSION_PREFIX}mgr"
mgr_ident="You are the Fleet MANAGER (tmux session '$mgr_sess'). Repo: $TARGET_REPO, base branch: $BASE_BRANCH, worktrees under: $WORKTREE_ROOT. Read fleet/roster.tsv for the worker list and use its 'session' column as the exact tmux target for every send-keys/capture-pane. Follow the fleet-manager skill: decompose, assign, poll for ===WORKER_DONE=== markers, verify against git + tests, then integrate. Do not write feature code yourself."
launch "$mgr_sess" "$TARGET_REPO" "$MANAGER_MODEL" "$mgr_ident"

echo
echo "Roster written to: $ROSTER"
echo "Attach:   tmux attach -t ${mgr_sess}        (or ${SESSION_PREFIX}worker-1, ...)"
echo "Kick off: fleet-send ${mgr_sess} \"<your feature request>\""
echo "Tear down: fleet-down${SESSION_PREFIX:+  (same SESSION_PREFIX in config)}"
