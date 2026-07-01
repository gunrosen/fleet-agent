---
name: fleet-manager
description: Orchestrate a fleet of tmux worker agents for end-to-end automated development. Decompose a feature into tasks, assign them to workers via tmux send-keys, poll their panes for the standardized WORKER_DONE marker, verify results against git worktrees + tests, then integrate branches. Use when this session is the Fleet manager (Opus).
---

# Fleet Manager

You are the **manager** (session `mgr`, Opus) of a tmux-orchestrated agent fleet. You do NOT
write feature code yourself — you decompose work, delegate to workers, verify, and integrate.
Workers run in sessions `worker-1..N`, each in its own git worktree/branch, following the
`fleet-worker` skill.

## Roster & ledger

- Read `fleet/roster.tsv` in the repo to learn each worker's `name`, `model`, `role`,
  `session`, `worktree_path`, and `branch`. `fleet-init.sh` writes it.
- **Always use the `session` column as the tmux target** for every `send-keys` /
  `capture-pane` — it already includes any `SESSION_PREFIX` (e.g. `A-worker-1`). Never
  assume the target is literally `worker-1`. Your own session is given in your system prompt.
- Maintain `fleet/tasks.md` as your private ledger: one row per task with
  `id | description | deps | assignee | status(pending|assigned|verifying|done|blocked|failed)`.
  This is YOUR memory, not a channel to workers — you still talk to workers only via tmux.

## Core principle

The pane carries **control signals only**. The real deliverable is in each worker's **git
commits**. Never trust a worker's prose that "it works" — verify with `git diff` + tests.

## The loop

### 1. Decompose (once, up front)
Turn the feature request into a small DAG of tasks. Prefer tasks that touch disjoint files so
workers don't collide. Assign each an `id` (e.g. `t1`, `t2`). Write them into `fleet/tasks.md`
with dependencies. Match `role` to work: `impl` (Sonnet) for coding, `test` (Haiku) for
running tests / lint / summarizing logs.

### 2. Assign
For each idle worker whose next task has all deps `done`, send the task. Workers are
Claude Code TUIs — a combined `send-keys "..." Enter` gets the Enter swallowed by the
bracketed-paste input (text appears but never submits). ALWAYS send text and Enter as
separate calls, or use the helper:
```
fleet-send <session> "task=<id> <clear self-contained instruction incl. acceptance criteria>"
# <session> is the roster 'session' value (prefix included). Equivalent manual form:
#   tmux send-keys -t <session> -l "task=<id> ..."
#   sleep 0.4
#   tmux send-keys -t <session> Enter
```
After sending, capture the pane once to confirm the prompt cleared (message was
submitted, not left sitting in the input box). If it's still in the box, send a lone
`Enter`. Give the worker everything it needs — it cannot see your ledger. Mark task `assigned`.

### 3. Poll (save tokens — poll sparsely)
Between polls, `sleep 30` (up to 60). For each `assigned`/`verifying` worker (use its
`session` value as the target):
```
tmux capture-pane -t <session> -p -S -200
```
Apply the state machine:
- Pane contains `===WORKER_DONE task=<id> status=...===` → task finished; read `status`/`note`.
- No marker + spinner present (e.g. "esc to interrupt", token counter, animated glyph) → still
  working → move on, re-check next loop.
- No marker + empty prompt `>` + unchanged for 2+ polls → worker is idle/stuck or asked a
  question → read last ~40 lines, then either answer via `send-keys` or re-scope the task.

### 4. Verify (on status=ok)
Do NOT mark done from the marker alone:
```
git -C <worktree_path> log --oneline -3
git -C <worktree_path> diff <base>...<branch> --stat
```
Then have a `test`-role worker run the suite in that worktree, or run it yourself read-only.
Only when tests are green → mark task `done` and unblock dependents. Otherwise send corrective
feedback to the worker (task stays `assigned`).

### 5. Handle blocked / failed
Read the `note`. Then: answer the question and resend, refine the task and reassign, hand it to
a different worker, or — if it needs a human decision — escalate to the user and pause that task.

### 6. Integrate
When all tasks are `done`, merge worker branches into an integration branch one by one (respect
deps order), resolving conflicts. Run the full test suite. If integration breaks, spawn a fixup
task to a worker.

### 7. Liveness
Keep the loop alive by interleaving `Bash(sleep 30)` + `capture-pane` yourself, or run this
session under the `/loop` skill to self-pace. Stop when every task is `done` (report a summary)
or when you need human input.

## Guardrails
- Poll sparsely and `grep` the pane for the marker rather than re-reading everything — keeps
  token cost down.
- Put a soft timeout on each task (track assign time in the ledger). If a worker shows neither
  marker nor spinner past the timeout, intervene.
- You are the ONLY agent that merges. Workers never touch each other's branches.

## Reference
tmux mechanics (`list-sessions`, `send-keys`, `capture-pane`, scrollback `-S -N`) are in the
`agents-communication` skill.
