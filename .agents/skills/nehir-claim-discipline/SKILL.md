---
name: nehir-claim-discipline
description: BEFORE writing fixed, works, resolved, bug found, confirmed, verified, root cause, or another success/root-cause claim in an answer, document, changeset, commit message, or worker handoff. Separates observed facts, hypotheses, mechanical validation, user testimony, and user-confirmed runtime behavior. Also activate when attributing a trace event to a code path or writing reproduction steps.
---

# Claim discipline: match every claim to its evidence

An unverified behavioral claim costs the user a wasted reproduction cycle. A
claim that later proves false also weakens trust in correctly verified work.
Report exactly what the evidence establishes—no less and no more.

## Distinguish five evidence levels

1. **Observed** — directly present in source, a trace, a screenshot, or command
   output. Include the concrete value, event, or `file:line` citation.
2. **User testimony** — the user reported it in conversation, but no artifact in
   this thread corroborates it. Record it if useful; never use it as evidence
   for or against a cause. Label it `unverified user testimony`.
3. **Hypothesis** — an inference that explains observations but has not been
   falsified or confirmed.
4. **Mechanically verified** — a specific tool result such as "the build
   passed", "the file was created", or "the trace contains event X". Report it
   plainly, but do not promote it into a behavioral success claim.
5. **User-confirmed runtime behavior** — the user reproduced the behavior in
   the real app and confirmed the result in this thread.

## Calibrate the wording

- `Fixed X` → `Changed X to do Y; runtime behavior is not yet confirmed.`
- `Works` → `The build passed; the runtime behavior still needs your repro.`
- `Found the root cause` → `Candidate cause: X. Observed evidence: Y.`
- `Verified` → name what was verified: `Verified that the emitted trace contains
  marker X`, not `Verified the fix`.
- `Viewport animated` / `relayout ran` / `window was revealed` → name the exact
  signal: `viewport target advanced`, `relayout was requested`, `phase stayed
  offscreen`. Engine-computed state is not the same as on-screen effect.

A code change, a passing build, and a fixed behavior are three different facts.
Never collapse them into one sentence.

## Bind events to emitters before interpreting them

Before using a trace event as evidence that a particular code path ran:

1. Find the source site that emits that exact `event=` / `context=` / `source=` /
   `phase=` / `reason=` string (`file:line`).
2. Confirm which user actions can produce it — and which cannot.
3. Do not attribute the event to a path that does not emit it.
4. If one click fans out to many events, say so; do not treat the count as
   independent confirmations of the same action.

## Check that the artifact can answer the question

If the claim needs a channel the capture does not contain (for example layout
execution logs, gesture events, or `phase=fired` when only `phase=scheduled` is
retained), label the claim `unverified` and name the missing observation. Do not
infer the missing channel from a related one.

Cumulative uptime counters are not per-capture evidence.

## Make claims falsifiable — and check the falsifier

Before asserting a cause or expected result:

1. State the observation that would prove the claim wrong.
2. Check for that observation when the available artifact permits it.
3. If it cannot be checked, label the claim `unverified` or `hypothesis`.
4. Tell the user exactly what to observe in the next repro.
5. Also check **consistency with signals that did fire**. A proposed cause that
   would have suppressed an observed signal (layout ran, intent recorded, focus
   completion scheduled, etc.) is already falsified by those signals. Discard it;
   do not restate it with a softer qualifier.

Do not invent symptoms or imply that an artifact contains evidence you have not
read. If you cannot reproduce the behavior, say so.

## Reproduction steps are claims

Reproduction steps must be consistent with the observed timeline and topology.
Do not invent steps from a hypothesis alone. Do not propose steps the capture
makes physically impossible (for example, clicking UI that only exists behind a
lock screen during a multi-second interactive capture). If no deterministic
recipe exists, write that explicitly.

## Repeated attempts

If the same behavior has resisted earlier attempts in this thread, lower
confidence rather than increasing certainty. State that this is another attempt
and do not claim it works. A falsified cause stays discarded.

## Exit condition

Use behavioral words such as `fixed`, `works`, and `resolved` only after the
user confirms that behavior in their real reproduction. Mechanical facts may
and should be reported as soon as they are actually verified, using precise
scope. User testimony without artifact corroboration stays labeled as such.
