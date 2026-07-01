#!/usr/bin/env bash
# fleet-send.sh — reliably deliver a message to a Claude Code TUI running in a tmux
# session. Sends the text and the submit Enter as SEPARATE key events with a short
# delay, because Claude Code's bracketed-paste input swallows a trailing Enter that
# arrives in the same send-keys call (text appears but never submits).
#
# Usage: ./fleet-send.sh <session> <message...>
#   ./fleet-send.sh worker-1 "task=t1 add slugify() to src/strings.js with tests"
#
set -euo pipefail

SESS="${1:?usage: fleet-send.sh <session> <message>}"; shift
MSG="$*"
DELAY="${FLEET_SEND_DELAY:-0.4}"   # bump if long messages still don't submit

tmux has-session -t "$SESS" 2>/dev/null || { echo "no such session: $SESS" >&2; exit 1; }

# 1) type the message literally (‑l avoids tmux interpreting tokens as key names)
tmux send-keys -t "$SESS" -l "$MSG"
# 2) let the TUI settle, then submit with a standalone Enter
sleep "$DELAY"
tmux send-keys -t "$SESS" Enter
