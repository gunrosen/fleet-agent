# Fleet — tmux-orchestrated AI agent army

A **manager** (Opus) decomposes a feature and delegates to **workers** (Sonnet to implement,
Haiku for narrow test/lint work), each isolated in its own **git worktree**. Agents talk over
plain tmux `send-keys` / `capture-pane`, coordinated by a standardized `===WORKER_DONE...===`
marker. The manager verifies every result with `git diff` + tests before integrating.

This repo is an **installable toolkit** (launcher-centric / "Model B"): the skills are installed
**globally** so any project on the machine can use them; you point the launcher at whichever
repo you want the fleet to work on.

## Layout

```
fleet/
├── install.sh            # install skills (global) + scripts (PATH) + config
├── uninstall.sh
├── skills/               # source of truth for the 3 skills
│   ├── agents-communication/   # base tmux send-keys/capture-pane mechanics
│   ├── fleet-manager/          # Opus orchestration loop
│   └── fleet-worker/           # worker discipline + DONE marker protocol
└── bin/
    ├── fleet-init.sh     # spin up manager + workers (worktrees + tmux)
    ├── fleet-send.sh     # reliable 2-step send to a Claude Code TUI (fixes swallowed Enter)
    ├── fleet-down.sh     # tear down (--wipe also removes worktrees)
    └── fleet.config.example
```

## Install (each new machine)

```bash
git clone <this-repo-url> fleet && cd fleet
./install.sh            # symlinks: git pull auto-updates. Use ./install.sh --copy for detached copies.
```

`install.sh` places:
- skills  → `~/.claude/skills/`  (loaded by every `claude` session, any cwd)
- scripts → `~/.local/bin/`      (`fleet-init`, `fleet-send`, `fleet-down` on PATH)
- config  → `~/.config/fleet/fleet.config`  (copied from the example if absent)

If `~/.local/bin` isn't on your PATH, add: `export PATH="$HOME/.local/bin:$PATH"`.

## Use

```bash
# 1) point the fleet at your project
$EDITOR ~/.config/fleet/fleet.config      # set TARGET_REPO, BASE_BRANCH, WORKERS

# 2) stand up the army (run in a REAL terminal — it launches autonomous agents)
fleet-init

# 3) give the manager a task (fleet-send handles the TUI Enter correctly)
fleet-send mgr "Add slugify() to src/strings.js with unit tests; npm test must pass"

# 4) watch
tmux attach -t mgr        # or worker-1, worker-2, ...   (Ctrl-b d to detach)

# 5) tear down
fleet-down --wipe
```

Config is resolved in this order: `--config <path>` → `$FLEET_CONFIG` → `./fleet.config` (cwd)
→ `~/.config/fleet/fleet.config`. So you can also drop a `fleet.config` in a project dir and run
`fleet-init` from there.

## The DONE marker protocol

Each worker ends a task with exactly one line:
```
===WORKER_DONE task=<id> status=<ok|blocked|failed> branch=<name> note=<short>===
```
The manager greps the pane for it, then verifies with `git diff` + tests. Only the manager
merges branches. Keep `note` short — `capture-pane` can wrap long lines.

## Gotchas baked into the design

- **Swallowed Enter**: sending `send-keys "text" Enter` to a Claude Code TUI often leaves the text
  unsubmitted (bracketed-paste eats the Enter). Always use `fleet-send` (text, delay, then a
  standalone Enter). Manager and workers are both TUIs — this applies to both.
- **File collisions**: never let two workers share a tree — each gets its own git worktree/branch.
- **Cost**: manager polls sparsely (30–60s) and greps for the marker instead of re-reading panes.
- **Safety**: `fleet-init` launches agents with `--dangerously-skip-permissions` by default so
  they run unattended. Drop that flag in `CLAUDE_FLAGS` (config) to keep approval gates.
