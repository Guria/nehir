---
name: nehir-doc-review
description: BEFORE writing or updating a discovery, plan, completed write-up, ticket, or other durable document that records a runtime bug, finding, or decision. Checks for ephemeral references, machine-specific paths, unanchored relative language, unsupported claims, stale status words, invented reproduction steps, and user testimony presented as fact.
---

# Durable-document review: self-contained and evidence-backed

A durable document must be readable with no access to the author's machine, no
access to a trace file, and no knowledge of when the text was written.

## Pre-save checklist

### 1. No ephemeral trace references

Do not cite trace filenames, line numbers inside local traces, "trace 1 / trace
2", or paths under `~/.local/state/nehir/traces/`. Inline the relevant events,
values, and identifiers into the document.

### 2. No machine-specific paths

Remove absolute home paths, worktree paths, Downloads paths, hostnames, and
other locations that another machine or CI cannot resolve.

### 3. Anchor relative language

Avoid dangling words such as `current`, `new`, `recent`, `previous`, `latest`,
or `before this`. Name the actual state, version, commit, event, or transition.
Relative wording is acceptable only when its anchor is explicit in the same
passage, such as "before the workspace reassignment event".

### 4. Support every factual claim

A factual statement needs at least one of:

- inlined evidence with concrete values or events;
- a durable `file:line` source citation;
- a named released version or commit;
- an explicit `hypothesis` label.

If the evidence does not establish the statement, narrow or remove it.

### 5. Inline enough evidence to reconstruct the reasoning

Include relevant numeric transitions, window tokens, pids, workspace/monitor
identifiers, lifecycle events, and reproduction topology. Do not write "see the
log".

### 6. Separate user testimony from artifact evidence

If the user reported a symptom that the capture does not corroborate (no matching
event, empty channel, or only cumulative counters), record it in an explicit
section such as "User-reported symptoms not established by this capture" and
label it `unverified user testimony`. Do not weave it into the causal argument
as if it were observed.

### 7. Precision on mechanical signals

Do not promote engine-computed or scheduled state into on-screen effect:

- viewport target advanced ≠ viewport animation reached the screen;
- relayout requested ≠ relayout executed;
- focus completion `phase=scheduled` ≠ focus applied;
- layout target frame computed ≠ AX frame written;
- interaction workspace advanced ≠ windows revealed.

Name the exact signal present in the evidence.

### 8. No invented reproduction steps

Reproduction steps must be consistent with the inlined timeline and topology.
If no deterministic recipe is known, say so. Do not invent steps from a
hypothesis, and do not propose steps the capture timeline makes impossible.
"Confirm the arming/gating condition in source before shipping repro steps"
applies: source-contradicted repro is not allowed.

### 9. Calibrate status words

Use `fixed`, `works`, or `resolved` only after the user confirms the runtime
behavior. Before that use precise states such as `observed`, `hypothesis`,
`proposed`, `implemented but unconfirmed`, or `under investigation`.

### 10. Re-read as a stranger

Check whether every sentence remains true and useful without session history.
Remove provenance chatter about the investigation process unless it is itself a
material constraint or decision. Prefer correcting an earlier wrong claim in
place over leaving a parallel document that still looks live.

## Exit condition

The document contains everything needed to verify its reasoning from durable
source and inlined evidence, with no dependency on local artifacts or unstated
time context, no user testimony presented as fact, and no invented reproduction
steps.
