---
name: nehir-review-triage
description: Triage review findings against the current code, classifying each as confirmed, stale, or false positive before any fix. Invoke explicitly with /nehir-review-triage when handed a list of review comments or an automated review report.
argument-hint: '<findings, PR number, or path to the report>'
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Edit, Agent, Bash(gh pr view:*), Bash(gh pr diff:*), Bash(git diff:*), Bash(git log:*), Bash(git show:*), Skill
---

# Triage review findings against the current code

FINDINGS: $ARGUMENTS

## Per finding

1. Open the cited file and line **in the current working tree**. Do not trust
   the review's framing of what the code does.
2. Classify:
   - `CONFIRMED` — still valid in the current code;
   - `STALE` — already addressed, moved, or superseded;
   - `FALSE POSITIVE` — contradicted by the current code.
3. Fix only confirmed findings. For every skip, give one short
   evidence-backed reason with a current `file:line` citation.

## Report

One line per finding, most severe first:

```
file:line — verdict — action taken, or the reason for skipping
```

Load `nehir-claim-discipline` before writing the report. `code changed` and
`runtime behavior fixed` are different facts — report mechanical validation
precisely and leave runtime behavior unconfirmed until the user verifies it.

## Independent opinion

When a finding is genuinely contested, delegate a single narrow question to the
`reviewer` subagent through the Agent tool: give it the file, the line, and the
specific claim to challenge, and require a `file:line`-backed answer. Treat what
comes back as a hypothesis to verify against the source yourself, not as
authority.

## Fences

- Do not touch tests. `nehir-test-edit-gate` applies unless the user has
  already unlocked it in this thread.
- Do not mutate git state. Read-only `git`/`gh` inspection is allowed.
- Keep the change set to the confirmed findings. Propose unrelated cleanups
  separately instead of folding them in.
