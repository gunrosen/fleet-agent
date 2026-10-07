# Fleet — tmux-orchestrated AI agent army

A **manager** (Opus) decomposes a feature and delegates to **workers** (Sonnet to implement,
Haiku for narrow test/lint work), each isolated in its own **git worktree/branch**. Agents talk
over plain tmux `send-keys` / `capture-pane`, coordinated by a `===WORKER_DONE...===` marker.
The manager verifies every result with `git diff` + tests, and is the only one that merges.

Installable toolkit ("Model B"): skills install **globally**, so any repo on the machine uses
them; you just point the launcher at whichever repo the fleet should work on.

## Layout

```
fleet/
├── install.sh / uninstall.sh   # install/remove skills + scripts + config
├── skills/                      # source of truth (symlinked into ~/.claude/skills)
│   ├── agents-communication/    # base tmux send-keys/capture-pane mechanics
│   ├── fleet-manager/           # Opus orchestration loop
│   └── fleet-worker/            # worker discipline + DONE marker protocol
└── bin/
    ├── fleet-init.sh            # spin up manager + workers (worktrees + tmux)
    ├── fleet-send.sh            # 2-step send to a Claude Code TUI (fixes swallowed Enter)
    ├── fleet-down.sh            # tear down sessions + every leftover process (--wipe: worktrees)
    ├── fleet-status.sh          # what is still running: per-session CPU/RAM, idle, orphans
    ├── fleet-proc.sh            # registry for agents' background processes (run/list/stop)
    ├── fleet-lib.sh             # shared helpers sourced by the scripts above
    └── fleet.config.example
```

## Install (per machine, once)

```bash
git clone <repo-url> fleet && cd fleet
./install.sh                 # symlinks (git pull auto-updates); use --copy for detached copies
```
Installs: skills → `~/.claude/skills/` · commands → `~/.local/bin/` (`fleet-init`,
`fleet-send`, `fleet-down`, `fleet-status`, `fleet-proc`) · config → `~/.config/fleet/fleet.config`.
Re-running `./install.sh` after a `git pull` picks up new commands (existing links are kept).
Add to PATH if needed: `export PATH="$HOME/.local/bin:$PATH"`.

## How it works

1. **Isolation** — each worker gets `git worktree add` on branch `fleet/<worker>`; workers never
   share a tree, so no file collisions. Only the manager merges.
2. **Delegation** — manager `fleet-send`s a `task=<id>` to a worker's tmux session.
3. **Completion signal** — worker commits, then prints one line the manager greps for:
   ```
   ===WORKER_DONE task=<id> status=<ok|blocked|failed> branch=<name> note=<short>===
   ```
4. **Verify, don't trust** — on `ok`, manager checks `git diff` + runs tests before marking done.
5. **Roster** — `fleet-init` writes `fleet/roster.tsv` (`name, model, role, session,
   worktree_path, branch`); the manager uses the **`session`** column as its exact tmux target.

## Use (single repo)

```bash
$EDITOR ~/.config/fleet/fleet.config     # set TARGET_REPO, BASE_BRANCH, WORKERS
fleet-init                               # run in a REAL terminal — launches autonomous agents
fleet-send mgr "Add slugify() to src/strings.js with tests; npm test must pass"
tmux attach -t mgr                       # watch (Ctrl-b d to detach)
fleet-status                             # what is running, CPU/RAM per session
fleet-down --wipe                        # stop everything + remove worktrees
```

## Use across multiple repos

Skills are global — **install once**, no per-repo duplication. What differs per repo is the
**config** and the **tmux session namespace**.

Give each project its own `fleet.config` (config resolves `--config` → `$FLEET_CONFIG` →
`./fleet.config` → `~/.config/fleet/fleet.config`) and a distinct `SESSION_PREFIX` so their
sessions don't collide:

```bash
# ~/project-A/fleet.config  →  TARGET_REPO=~/project-A   SESSION_PREFIX="A-"
cd ~/project-A && fleet-init             # sessions: A-mgr, A-worker-1, ...
fleet-send A-mgr "feature for A"

# ~/project-B/fleet.config  →  TARGET_REPO=~/project-B   SESSION_PREFIX="B-"
cd ~/project-B && fleet-init             # sessions: B-mgr, B-worker-1, ...
fleet-send B-mgr "feature for B"

tmux ls                                  # A-* and B-* coexist
cd ~/project-A && fleet-down --wipe      # tear down A (same SESSION_PREFIX in its config)
```
Empty `SESSION_PREFIX` (default) keeps plain names (`mgr`, `worker-1`) for single-project use.
Worktrees default to `$TARGET_REPO/../fleet-wt`, so they're already separated per repo.

## Lifecycle & cleanup

**Closing the terminal tab does not stop the fleet.** The tmux server is detached from any
terminal (`ppid 1`); closing the tab only detaches the client. Agents, their MCP servers and any
dev server they started keep running — and keep using CPU, RAM and tokens — until `fleet-down`.

- `fleet-status` — per session: attached?, idle time, process count, CPU% and RSS of the whole
  process tree; plus registered background processes and orphans inside the worktrees.
- `fleet-down` — collects every process **before** closing the sessions (agent + MCP servers +
  background shells, registered `fleet-proc` jobs, `ppid 1` orphans whose cwd is in
  `WORKTREE_ROOT`), closes the sessions, then SIGTERM → wait `KILL_GRACE` s → SIGKILL.
  Background shells an agent starts run in their own process session, so a plain
  `tmux kill-session` never reaches them. `fleet-down --dry-run` previews the list.
- `fleet-proc run <label> -- <cmd>` — agents start long-running processes through this (the
  skills require it). It records PID + start time in `$TARGET_REPO/fleet/procs.tsv` and `exec`s
  the command, so the process stays traceable even after the agent that started it dies.
  `fleet-proc list` / `fleet-proc stop <label|pid|--all>`.

## Gotchas baked into the design

- **Swallowed Enter** — `send-keys "text" Enter` to a Claude Code TUI often leaves text
  unsubmitted (bracketed-paste eats the Enter). Always use `fleet-send`. Manager and workers are
  both TUIs.
- **Parallel repos** — tmux session names are global; use a distinct `SESSION_PREFIX` per repo.
- **Cost** — manager polls sparsely (30–60s) and greps for the marker instead of re-reading panes.
- **Safety** — `fleet-init` launches agents with `--dangerously-skip-permissions` by default.
  Drop it in `CLAUDE_FLAGS` (config) to keep approval gates.
