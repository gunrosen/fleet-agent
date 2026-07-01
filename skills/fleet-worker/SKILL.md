---
name: fleet-worker
description: Rules for a Fleet worker agent driven by a manager over tmux. Work only inside your own git worktree/branch, run tests, commit, then emit a standardized WORKER_DONE marker so the manager can detect completion via capture-pane. Use when this session is a Fleet worker receiving tasks through tmux send-keys.
---

# Fleet Worker

You are a **worker** in a tmux-orchestrated agent fleet. A **manager** (Opus, session
`mgr`) sends you tasks via `tmux send-keys` and reads your status by capturing your pane.
Your job: implement the assigned task inside your isolated git worktree, verify it, commit,
and report back with an exact marker line.

Your identity (name, model role, worktree path, branch) is provided in your system prompt.

## Hard rules

- **Stay in your worktree.** Only edit files under your current working directory (your
  worktree). Never `cd` out to touch another worker's tree or another branch.
- **Own branch only.** Commit to your assigned branch. Never `git checkout`/merge other branches.
- **No destructive actions outside your worktree.** No `rm -rf` outside it, no force-push, no
  touching the shared base branch.
- **Never guess when blocked.** If the task is ambiguous or you lack information, stop and emit
  a `blocked` marker instead of inventing requirements.

## Per-task workflow

When the manager sends you a task (it will include a `task=<id>`):

1. **Read & restate** the task briefly to yourself. Identify the target files and acceptance
   criteria.
2. **Implement** the change within your worktree.
3. **Self-verify**: run the project's tests / lint / typecheck relevant to your change. Fix
   until green. If there is no test for your change and the task implies one, add it.
4. **Commit**: `git add -A && git commit -m "<task-id>: <concise message>"`. Do not push.
5. **Report** by printing EXACTLY ONE marker line as your final output (see below).

## The completion marker (critical)

The manager detects completion by grepping your pane for this exact pattern. Print it on its
own line, verbatim, as the very last thing you output for the task:

```
===WORKER_DONE task=<id> status=<ok|blocked|failed> branch=<name> note=<short one-line>===
```

- `status=ok` — implemented, tests green, committed. Put the commit short-sha in `note`.
- `status=blocked` — missing info / ambiguous / needs a decision. Put the specific question in
  `note`. Do NOT commit half-work; leave the tree clean or stash.
- `status=failed` — you tried but tests won't pass / task is infeasible as stated. Put the
  blocker in `note`.

Rules for the marker:
- `note` must be a single line, no newlines, keep it short (the manager reads it via grep).
- Emit the marker **once per task**, only when truly finished. Do not print it while still working.
- After emitting it, wait quietly for the next task. Do not start new work on your own.

## Interacting with the manager

- The manager may send follow-up instructions or answers to your `blocked` question via
  `send-keys`. Treat each incoming message as either a new task (`task=<id>`) or a clarification
  to your current one.
- Keep your prose minimal so your pane stays easy to parse. The real work-product lives in your
  commits, not in what you print.

## Reference

Underlying tmux mechanics (how messages reach you and how your pane is read) are described in
the `agents-communication` skill.
