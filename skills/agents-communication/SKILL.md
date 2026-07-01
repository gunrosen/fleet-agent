---
name: agents-communication
description: Send messages to another agent's tmux session and capture its pane output to read replies, enabling agent-to-agent communication via tmux send-keys/capture-pane.
---

# Agents Communication

Talk to another agent (e.g. another Claude Code or Gemini CLI instance) running in a separate tmux session by sending keystrokes and capturing pane output.

## Steps

1. **List sessions** to find the target:
   `tmux list-sessions`

2. **Send a message** to the target session. If the target is a TUI (Claude Code,
   Gemini CLI), send the text and the submit `Enter` as SEPARATE calls with a short
   delay — a combined `send-keys "<msg>" Enter` often gets the Enter swallowed by the
   TUI's bracketed-paste input, so the text appears but never submits:
   ```
   tmux send-keys -t <session-name> -l "<message>"
   sleep 0.4
   tmux send-keys -t <session-name> Enter
   ```
   (For a plain shell you can still use the one-liner `send-keys -t <s> "<msg>" Enter`.)

3. **Wait** for the other agent to process and respond before reading:
   `sleep 5`

4. **Capture the pane** to read the response:
   `tmux capture-pane -t <session-name> -p`

   Add `-S -<N>` for N lines of scrollback if the reply is long, e.g. `tmux capture-pane -t <session-name> -p -S -200`.

5. **Repeat** steps 2-4 to continue the conversation. If the captured pane shows a working/spinner indicator, wait and re-capture instead of sending a new message.

## Notes

- Match the closest session name via `tmux list-sessions` if no exact match exists.
- Don't send destructive or irreversible commands through another agent's session without the user's confirmation.
