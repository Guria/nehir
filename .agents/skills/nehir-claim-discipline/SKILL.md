---
name: nehir-claim-discipline
description: BEFORE writing fixed, works, resolved, bug found, confirmed, verified, or another success/root-cause claim in an answer, document, changeset, commit message, or worker handoff. Separates observed facts, hypotheses, mechanical validation, and user-confirmed runtime behavior.
---

# Claim discipline: match every claim to its evidence

An unverified behavioral claim costs the user a wasted reproduction cycle. A
claim that later proves false also weakens trust in correctly verified work.
Report exactly what the evidence establishes—no less and no more.

## Distinguish four evidence levels

1. **Observed** — directly present in source, a trace, a screenshot, or command
   output. Include the concrete value, event, or `file:line` citation.
2. **Hypothesis** — an inference that explains observations but has not been
   falsified or confirmed.
3. **Mechanically verified** — a specific tool result such as "the build
   passed", "the file was created", or "the trace contains event X". Report it
   plainly, but do not promote it into a behavioral success claim.
4. **User-confirmed runtime behavior** — the user reproduced the behavior in
   the real app and confirmed the result in this thread.

## Calibrate the wording

- `Fixed X` → `Changed X to do Y; runtime behavior is not yet confirmed.`
- `Works` → `The build passed; the runtime behavior still needs your repro.`
- `Found the root cause` → `Candidate cause: X. Observed evidence: Y.`
- `Verified` → name what was verified: `Verified that the emitted trace contains
  marker X`, not `Verified the fix`.

A code change, a passing build, and a fixed behavior are three different facts.
Never collapse them into one sentence.

## Make claims falsifiable

Before asserting a cause or expected result:

1. State the observation that would prove the claim wrong.
2. Check for that observation when the available artifact permits it.
3. If it cannot be checked, label the claim `unverified` or `hypothesis`.
4. Tell the user exactly what to observe in the next repro.

Do not invent symptoms or imply that an artifact contains evidence you have not
read. If you cannot reproduce the behavior, say so.

## Repeated attempts

If the same behavior has resisted earlier attempts in this thread, lower
confidence rather than increasing certainty. State that this is another attempt
and do not claim it works.

## Exit condition

Use behavioral words such as `fixed`, `works`, and `resolved` only after the
user confirms that behavior in their real reproduction. Mechanical facts may
and should be reported as soon as they are actually verified, using precise
scope.
