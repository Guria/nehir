---
name: nehir-retry-with-new-trace
description: Re-open an investigation after an attempted fix failed and the user captured a new trace from a build containing that attempt. Invoke explicitly with /nehir-retry-with-new-trace when the symptom survived the change.
argument-hint: '<new trace path> [nehir issue number or discovery document]'
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Write, Edit, Agent, Skill, Bash(git log:*), Bash(git show:*), Bash(git diff:*), Bash(git status:*)
---

# Retry after a failed fix, with a new trace

TRACE AND SUBJECT: $ARGUMENTS

The user has already spent a build and a reproduction cycle on an attempt that
did not work. The failure mode this skill exists to prevent is restating the
same hypothesis with more confidence, or patching whatever the newest trace
happens to show. Confidence goes **down** on entry, not up.

If the trace was not named, ask for it. If the attempted change is not
identified, ask which branch, worktree, or commit the build came from — without
it, nothing below can be grounded.

## 1. Establish what the build actually contained

Before reading the trace, pin the artifact under test:

- Identify the branch/commit of the attempted change and read its diff
  (`git show`, `git diff`). State the intervention in one sentence: which
  mechanism it changed and what it was supposed to prevent.
- If the attempt shipped temporary instrumentation, confirm a known marker from
  it appears **in the trace the user just captured**. Seeing the marker in
  another logging subsystem does not count.
- If the changed code path leaves no evidence in the trace, say so. A trace
  that cannot show whether the intervention ran can neither falsify nor confirm
  it; the next step is instrumentation, not another guess.

Do not proceed to conclusions while it is still unknown whether the build under
test contained the change.

## 2. Retire the previous hypothesis explicitly

Write down, before any new theory:

- the prior candidate cause and the falsifier recorded for it;
- what the new trace shows about that falsifier;
- one verdict: `falsified`, `unfalsified but insufficient`, or
  `partly correct, incomplete`.

Load `nehir-claim-discipline` and apply its "repeated attempts" rule: when a
behavior has resisted an attempt, lower confidence rather than reasserting the
same explanation in stronger language. Discard a falsified cause; do not carry
it forward with a softened qualifier.

## 3. Read the new trace as first-class evidence

Observe before explaining, exactly as in a fresh discovery: inventory which
channels the capture contains, then record concrete events, numeric state,
window tokens, workspace and monitor identifiers, reproduction topology. Cite
`file:line` for every source claim. Bind each relied-on event to its source
emitter before interpreting it (see `nehir-claim-discipline`).

Compare against the values **inlined in the existing discovery document**, not
against a previous trace file and not against memory. If a needed value was
never inlined, that is a defect in the document — inline it now from the
evidence at hand or mark it unavailable.

Keep user testimony that the new capture does not corroborate labeled as
`unverified user testimony`; do not promote it into the causal argument.

State plainly whether the symptom kept the same shape or changed shape. A
changed shape is a finding, not a detail.

## 4. Classify the failure mode

This classification decides the next step. Name exactly one and cite the
evidence for it:

- **Wrong cause** — the intervention landed and ran, and the mechanism producing
  the symptom was never touched. Go back to discovery.
- **Right cause, wrong or incomplete intervention** — the mechanism is
  implicated, but the change does not enforce the invariant across the input
  space. Re-plan the intervention, not the diagnosis.
- **Cause addressed, second path produces the same symptom** — the original path
  is now clean in the trace and a different path reaches the same visible state.
  Treat it as a new discovery that shares a symptom.
- **Regression** — the attempt introduced behavior that was not present before
  it. Say so explicitly and treat reverting as the default.

"It is probably a timing issue" is not a classification. If the evidence does
not support any of the four, say the trace is insufficient and name the
observation that would separate them.

## 5. Decide the fate of the failed change

Recommend `keep`, `narrow`, or `revert`, with the reason. A change that is
correct but insufficient may be worth keeping; a change that is inert or
harmful should not stay in the tree to keep a later diff readable.

`nehir-git-mutation-gate` applies. Reverting, resetting, restoring, and branch
operations each need explicit permission for that exact action. Never alter
work the user created in the tree or index.

## 6. Update the existing durable record

Amend the discovery or plan that drove the failed attempt. Do not open a second
document describing the same symptom — a parallel record makes the falsified
hypothesis look live.

Add to the existing document:

- a falsification section: what was attempted, what the evidence showed, the
  verdict from step 2;
- the new evidence, inlined as values and events;
- the revised candidate cause with its own explicit falsifier.

Load `nehir-doc-review` and apply its checklist before saving: no trace
filenames, no machine-local paths, no unanchored `current`/`previous`/`latest`,
durable `file:line` citations, status words matched to evidence. Planning
artifacts live in the plans worktree; read that worktree's `AGENTS.md` first.

## 7. Re-plan only after the mechanism is named

Load `nehir-solution-robustness`. On a second attempt the pull toward a
symptom-shaped patch is strongest, so the additional bars are:

- Do not introduce a constant, timing value, or special case whose only
  justification is that it makes this reproduction pass.
- Do not add a boolean flag to route around the case the trace showed.
- State the invariant the new intervention enforces and the boundary cases it
  holds across — different item counts, monitor geometries, and the lifecycle
  points of entry, steady state, interruption, and cleanup.

## 8. Escalate instead of guessing a third time

When two attempts against the same candidate cause have failed, stop iterating
alone. Either:

- delegate one narrow contested claim to the `reviewer` subagent, with the file,
  the line, and the assertion to challenge, and require a `file:line`-backed
  answer — then verify it against the source yourself; or
- ship targeted temporary instrumentation instead of another fix. Per
  `AGENTS.md`, temporary bug-tracing code is **never** gated behind a feature
  flag, environment variable, or verbosity setting: emit it unconditionally to
  the exact sink the user will inspect, and confirm the marker reaches the
  captured artifact before asking for a reproduction.

## Fences for this run

- Do not modify anything under `Sources/` until the user approves the revised
  plan. Temporary instrumentation is the exception, and only in a throwaway
  worktree, unconditional, agreed with the user first.
- Do not add, modify, run, compile, delete, or move tests.
  `nehir-test-edit-gate` applies for the whole run.
- Do not mutate git state. Read-only `git log`, `git show`, `git diff`, and
  `git status` are allowed.

## Exit condition

The previous hypothesis has an explicit verdict, the failure mode is classified
with evidence, the durable document is updated in place, and either a revised
plan or an instrumentation step is waiting for the user's approval. No
behavioral success word is used anywhere until the user confirms the behavior in
their own reproduction.
