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

1. **Inventory the artifact before explaining.** List which channels the capture
   actually contains (and which are empty or cumulative-only). State up front
   which questions this artifact can answer and which it cannot. A claim that
   needs a missing channel is `unverified` until a capture that has it exists.
2. **Observe before explaining.** Read the trace and the relevant `Sources/`
   files. Write down observations first — concrete events, numeric state,
   window tokens, workspace and monitor identifiers, timestamps of each user
   action. Cite `file:line` for every source claim. Do not jump to a cause.
3. **Bind every trace event to its emitter before interpreting it.** For each
   decision/trace event you rely on, find the source site that emits that exact
   `event=` / `context=` / `source=` / `phase=` / `reason=` string and confirm
   which user action (if any) can produce it. Do not attribute an event to a
   code path that does not emit it. One user action may fan out to many events;
   many events do not imply many independent user actions.
4. **Separate three symptom layers.** Keep them distinct for the whole run:
   - **User-reported, not in the artifact** — the user said it, the capture has
     no corroborating event. Label it `unverified user testimony`. Never use it
     as evidence for or against a cause.
   - **Artifact-observed** — values, events, transitions present in the capture
     or in durable source.
   - **Source-mapped mechanism** — a `file:line` path that could produce the
     artifact-observed signals; still a hypothesis until its falsifier is
     checked.
5. **Form one candidate cause and state its falsifier.** Name the observation
   that would prove the cause wrong, then look for that observation in the
   available evidence. If it cannot be checked from what exists, label the
   cause `unverified`. A candidate cause must also be **consistent with every
   signal that did fire**, not only with the missing effect: if the proposed
   guard would have suppressed the layout engine entirely, the layout engine
   must not have run. A contradiction kills the candidate; do not soft-pedal it.
6. **Calibrate every claim.** Load the `nehir-claim-discipline` skill and apply
   it. Do not write `found`, `fixed`, or `works`. Keep observed evidence,
   hypothesis, mechanical validation, and user-confirmed runtime behavior
   separate. Distinguish "the engine computed / recorded X" from "X reached the
   screen or the AX layer".
7. **Write the discovery in the plans worktree.** Load the `nehir-doc-review`
   skill and apply its checklist before saving. The document must be readable
   with no access to the author's machine:
   - inline the events, values, identifiers, and reproduction topology that
     establish the finding;
   - no trace filename, local trace path, worktree path, Downloads path, or
     hostname;
   - anchor relative wording to a named state, event, or commit;
   - cite durable `file:line` source locations;
   - include an explicit section for user-reported symptoms that the artifact
     does not corroborate;
   - write reproduction steps only when they are consistent with the observed
     timeline and topology. If no deterministic recipe exists, say so — do not
     invent steps inferred from a hypothesis, and do not propose steps the
     capture timeline makes physically impossible.
8. **Propose a plan, not an implementation.** Load `nehir-solution-robustness`
   and apply it: fix the shared mechanism, derive any constant from inputs or
   documented measurements, cover the boundary cases, write no migration code
   for unreleased state, and keep unrelated refactors out. If the candidate
   cause is still `unverified` because the artifact lacks a channel, the next
   step is targeted instrumentation or a better capture — not a code fix.

## Fences for this run

- Do not modify anything under `Sources/` until the user approves the plan.
  Temporary instrumentation is the exception, and only in a throwaway worktree,
  unconditional, agreed with the user first (see `AGENTS.md`).
- Do not add, modify, run, compile, delete, or move tests. The
  `nehir-test-edit-gate` rule applies for the whole run.
- Do not mutate git state. Read-only `git log`, `git show`, and `git diff` are
  allowed.

## Exit condition

A saved discovery document that is self-contained, separates user testimony from
artifact evidence, states a candidate cause with an explicit falsifier (or
explicitly labels the cause `unverified` and names the missing observation), and
either a proposed plan or an instrumentation/capture step awaiting the user's
approval. No invented reproduction steps. No behavioral success word until the
user confirms the behavior in their own reproduction.
