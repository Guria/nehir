# Agent assets

`.agents/` is the repository source of truth for shared agent skills, reusable
fence text, and gate hook scripts.

## Layout

| Path | Contents |
| --- | --- |
| `skills/<name>/SKILL.md` | Project skills. Each one registers `/<name>` as a slash command. |
| `shared/fences/*.md` | Fence blocks that skills and delegated tasks read at run time instead of duplicating. |
| `hooks/*.sh` | `PreToolUse` gate scripts. Wiring them into settings is a separate opt-in step (see below). |

Subagent definitions live in `.claude/agents/*.md` as real files, not symlinks:
per-skill symlinks under `.claude/skills/` are a documented Claude Code feature,
while symlinked agent definitions are not, so agents are kept where the harness
expects them.

## Skills

Two kinds share one directory:

**Gates** activate on their own when their trigger condition appears. They carry
no `disable-model-invocation`, so the model loads them by description.

- `nehir-test-edit-gate` — before touching or running any test.
- `nehir-git-mutation-gate` — before any git mutation.
- `nehir-claim-discipline` — before writing a success or root-cause claim.
- `nehir-solution-robustness` — before finalizing a fix.
- `nehir-doc-review` — before saving a durable document.

**Workflows** run only when invoked as a slash command. They set
`disable-model-invocation: true` so they never fire on their own. They are
listed in the order the work usually moves through them.

- `/nehir-bug-discovery [trace] <symptom>` — trace-driven, source-backed
  investigation ending in a self-contained discovery and a proposed plan.
- `/nehir-retry-with-new-trace <trace> [#NN]` — re-open the investigation after
  an attempted fix failed and a new trace was captured from a build containing
  it: retire the prior hypothesis, classify the failure mode, update the
  existing discovery in place.
- `/nehir-delegate-lane <cluster>` — scope one isolated lane, bootstrap it, and
  hand it to the `lane-worker` subagent with both fences attached.
- `/nehir-finalize-change [#NN]` — changeset fragment and commit message, with
  every git action still gated.
- `/nehir-review-triage <findings>` — classify findings against the current code
  as confirmed, stale, or false positive before fixing anything.

`argument-hint` ordering convention: every workflow reads the whole invocation
through `$ARGUMENTS`, so the hint's order is advice to the human, not a
positional signature. Put concrete references — a trace path, an issue number, a
document — first, and free prose last, because prose has no terminator and
anything written after it is ambiguous to read back. Requiredness is carried by
`<>` versus `[]`, not by position.

## Subagents

- `lane-worker` — implements one file-scoped cluster in its own git worktree
  (`isolation: worktree`), with the gate skills preloaded. Returns a summary, so
  the work does not consume the calling session's context.
- `reviewer` — read-only second opinion on one narrow claim. Tools are limited
  to `Read`, `Grep`, and `Glob`, so it can only cite source, never change it.

## Gate hooks

`hooks/git-mutation-gate.sh` and `hooks/test-edit-gate.sh` are `PreToolUse`
scripts that raise a permission prompt (`permissionDecision: "ask"`) for git
mutations and for test edits or test runs. A skill tells the model a rule; these
hooks make the harness stop and ask regardless of what the model intended, and
the answer applies to that one action only.

They are **not wired up by default**. `.claude/settings.json` is the shared
project settings file but is currently git-ignored and holds machine-local
configuration, so enabling the hooks requires deciding where that local
configuration should live first.

To enable them, add to `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.agents/hooks/git-mutation-gate.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.agents/hooks/test-edit-gate.sh" }
        ]
      },
      {
        "matcher": "Edit|Write|MultiEdit|NotebookEdit",
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.agents/hooks/test-edit-gate.sh" }
        ]
      }
    ]
  }
}
```

Both scripts require `jq` and exit silently for anything they do not match.
`mise run test:compile` raises the prompt by design: `docs/TESTING.md` defers
compiling tests along with writing and running them.

## Claude Code discovery

`.claude/skills/<name>` is a relative symlink to `.agents/skills/<name>`, one
per skill. Adding a skill means creating both the directory and its symlink:

```bash
ln -sfn "../../.agents/skills/<name>" ".claude/skills/<name>"
```

Machine-local Claude state stays under `.claude/`; `.gitignore` excludes the
settings files and worktree paths while leaving the skill symlinks and agent
definitions tracked.
