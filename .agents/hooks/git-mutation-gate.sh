#!/bin/sh
# PreToolUse hook (matcher: Bash).
#
# Turns AGENTS.md "git mutations require explicit per-action permission" into a
# mechanical prompt: every git-mutating command raises a permission request
# instead of running silently. The user's answer is the per-action permission,
# and it never carries to the next command.
#
# Emits `ask` (not `deny`) so authorized work stays one keystroke away.
# Read-only git commands pass through untouched.

set -eu

JQ=/usr/bin/jq
command -v "$JQ" >/dev/null 2>&1 || JQ=jq

input=$(cat)
command_line=$(printf '%s' "$input" | "$JQ" -r '.tool_input.command // ""')

[ -n "$command_line" ] || exit 0

# A git invocation, optionally with global flags (including `-C <dir>`),
# followed by a mutating subcommand as a whole word.
mutating='(^|[^A-Za-z0-9_./-])git([[:space:]]+-[A-Za-z-]+([[:space:]]+[^[:space:]-][^[:space:]]*)?)*[[:space:]]+(add|am|apply|branch|checkout|cherry-pick|clean|commit|fetch|merge|mv|pull|push|rebase|reset|restore|revert|rm|stash|switch|tag|worktree)([[:space:]]|$)'

if printf '%s' "$command_line" | grep -Eq "$mutating"; then
  reason='This command mutates git state. AGENTS.md requires explicit permission for this exact action; permission does not chain from an earlier approval, and changes the user created in the working tree or index must not be altered. Approve only if this specific action was requested.'
  "$JQ" -n --arg r "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $r
    }
  }'
fi

exit 0
