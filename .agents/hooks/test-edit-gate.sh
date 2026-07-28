#!/bin/sh
# PreToolUse hook (matchers: Edit|Write|MultiEdit|NotebookEdit and Bash).
#
# Turns the docs/TESTING.md sequencing gate into a mechanical prompt: touching
# or running tests raises a permission request instead of happening as a side
# effect of some other task. The gate unlocks when the user confirms the
# behavior works in their real reproduction, or explicitly asks for test work —
# and approving the prompt is how that unlock is expressed.
#
# This is a sequencing rule, not a preservation rule: after the gate unlocks,
# existing tests may legitimately be rewritten or deleted.
#
# Emits `ask` (not `deny`) so authorized test work stays one keystroke away.

set -eu

JQ=/usr/bin/jq
command -v "$JQ" >/dev/null 2>&1 || JQ=jq

input=$(cat)
tool=$(printf '%s' "$input" | "$JQ" -r '.tool_name // ""')

ask() {
  "$JQ" -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

case "$tool" in
  Bash)
    command_line=$(printf '%s' "$input" | "$JQ" -r '.tool_input.command // ""')
    [ -n "$command_line" ] || exit 0
    running='(^|[^A-Za-z0-9_./-])(mise[[:space:]]+run[[:space:]]+test|swift[[:space:]]+test|xcodebuild[[:space:]].*[[:space:]]test([[:space:]]|$))'
    if printf '%s' "$command_line" | grep -Eq "$running"; then
      ask 'This runs the test suite. docs/TESTING.md defers all test work — including running tests — until the user confirms the behavior works in their real reproduction or explicitly asks for test work. A plan'"'"'s test phase does not unlock the gate.'
    fi
    ;;
  Edit|Write|MultiEdit|NotebookEdit)
    path=$(printf '%s' "$input" | "$JQ" -r '.tool_input.file_path // .tool_input.notebook_path // ""')
    [ -n "$path" ] || exit 0
    case "$path" in
      */Tests/*|*Tests.swift|*Test.swift)
        ask 'This edits a test file. docs/TESTING.md defers all test work to the latest stage: no adding, modifying, rewriting, deleting, or moving tests until the user confirms the behavior works or explicitly asks for test work. New tests also belong in small per-behavior files, never appended to the frozen legacy monoliths.'
        ;;
    esac
    ;;
esac

exit 0
