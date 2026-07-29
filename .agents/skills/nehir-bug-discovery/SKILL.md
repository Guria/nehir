---
name: nehir-bug-discovery
description: Run a trace-driven, source-backed bug discovery and produce a self-contained discovery document plus a proposed plan. Invoke explicitly with /nehir-bug-discovery when a runtime symptom needs investigation before any code change.
argument-hint: '[trace path] <symptom>'
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash(git log:*), Bash(git show:*), Bash(git diff:*), Write, Edit, Skill
---

# Trace-driven bug discovery

TRACE AND SYMPTOM: $ARGUMENTS

If the symptom is missing, ask for it before starting. If no trace was named,
ask whether one exists rather than assuming.

## Sequence

1. **Observe before explaining.** Read the trace and the relevant `Sources/`
   files. Write down observations first — concrete events, numeric state,
   window tokens, workspace and monitor identifiers. Cite `file:line` for every
   source claim. Do not jump to a cause.
2. **Form one candidate cause and state its falsifier.** Name the observation
   that would prove the cause wrong, then look for that observation in the
   available evidence. If it cannot be checked from what exists, label the
   cause `unverified`.
3. **Calibrate every claim.** Load the `nehir-claim-discipline` skill and apply
   it. Do not write `found`, `fixed`, or `works`. Keep observed evidence,
   hypothesis, mechanical validation, and user-confirmed runtime behavior
   separate.
4. **Write the discovery in the plans worktree.** Load the `nehir-doc-review`
   skill and apply its checklist before saving. The document must be readable
   with no access to the author's machine:
   - inline the events, values, identifiers, and reproduction topology that
     establish the finding;
   - no trace filename, local trace path, worktree path, Downloads path, or
     hostname;
   - anchor relative wording to a named state, event, or commit;
   - cite durable `file:line` source locations.
5. **Propose a plan, not an implementation.** Load `nehir-solution-robustness`
   and apply it: fix the shared mechanism, derive any constant from inputs or
   documented measurements, cover the boundary cases, write no migration code
   for unreleased state, and keep unrelated refactors out.

## Fences for this run

- Do not modify anything under `Sources/` until the user approves the plan.
- Do not add, modify, run, compile, delete, or move tests. The
  `nehir-test-edit-gate` rule applies for the whole run.
- Do not mutate git state. Read-only `git log`, `git show`, and `git diff` are
  allowed.

## Exit condition

A saved discovery document that is self-contained, a candidate cause with an
explicit falsifier, and a proposed plan awaiting the user's approval.
