# Plan: classify and triage pre-existing local test failures on main

You are in a throwaway worktree (`diagnose/main-test-baseline`, at `afc68733`,
the exact commit CI reports green). The repo reports 10 test failures locally
that CI does not. Your job is to classify them, not to fix production bugs.

**Do not spawn subagents. Do all work yourself in this session.**

## What you are authorized to do (the test gate is UNLOCKED for THIS task only)

This task is an explicit exception to `docs/TESTING.md`'s "defer all test work"
rule. You MAY, for this task only:

- run and re-run tests (`mise run test`, filtered test runs) to measure flakiness;
- read and inspect tests and the `Sources/` they exercise (read-only on `Sources/`);
- **delete** individual tests that you judge fragile or valueless, per the
  "Deleting legacy tests" section of `docs/TESTING.md` — rolling, judged deletion
  is the sanctioned path, with the reasoning recorded in the commit body;
- write a classification document (see below).

You are NOT authorized to:

- modify anything under `Sources/`. If a failure turns out to be a **real bug**
  (production code wrong, test correct), do NOT fix it and do NOT delete the
  test. Record it as "real defect — production fix needed, out of scope" and move on.
- delete a test you are not confident is fragile/valueless. When unsure, keep it
  and mark the recommendation `needs-human-review`.
- rewrite a frozen-monolith test in place. If a test's *contract* is valid but
  its *form* is fragile, propose (do not implement) extracting it to a small
  per-behavior file in the classification doc.
- run `mise run check`/`ci` as a substitute gate — use the explicit commands below.

Read `docs/TESTING.md` in full before touching any test file. In particular note
which files are **frozen monoliths** (never append to them): `AXEventHandlerTests.swift`,
`LayoutRefreshControllerTests.swift`, and the others it names. Deleting individual
fragile tests *from* a frozen monolith is allowed; appending or rewriting-in-place
is not.

## Starting evidence

`.agents/main-test-failure-baseline.md` is a self-contained baseline: the 10
failures, their assertion text, `file:line`, and observed-vs-expected values,
captured from one `mise run test` on this commit. CI on `afc68733` is green.
Read it first; do not assume anything beyond what it states.

The 10 failures span 3 suites / 4 tests:

1. `AXEventHandlerTests.nonFocusedFrameChangedMatchingLastAppliedFrameDoesNotRelayout`
   — `observedReadCount 0==1`, `geometryRelayoutsSuppressed 0==1` (frozen monolith).
2. `AXEventHandlerTests.parentedStandardChildDoesNotRetileNiriParent`
   — parent column width delta `556` vs `<0.5` (frozen monolith).
3. `LayoutRefreshControllerTests.executeLayoutPlanShowWithCachedVisibleFrameClearsHiddenStateWithoutRevealTransaction`
   — `attemptCount 1==0` (frozen monolith).
4. `WMControllerFocusTests.genericUnmanagedFocusDoesNotSuppressInactiveWorkspaceActivation`
   — active workspace / focusedHandle / borderTarget mismatches (5 issues).

## Phase 1 — Measure flakiness (mechanical)

For each of the 4 tests, determine determinism. Do this BEFORE reading source, so
the numbers are unbiased:

1. Re-run the **full suite once more** (`mise run test`) on this clean worktree
   and diff the failure set against the baseline. Record whether the same 10
   reproduce (same assertions, same observed values) or whether anything changed.
2. Run **each of the 4 failing tests in isolation**, 3 times each. Use the
   filtered form, e.g.:
   `mise run test -- --filter 'AXEventHandlerTests/nonFocusedFrameChangedMatchingLastAppliedFrameDoesNotRelayout'`
   (confirm the exact filter syntax against `mise run test -- --help` /
   `swift test --help` first; the project uses swift-testing). Record pass/fail
   and the observed value each run.
3. For any test that **passes sometimes**, that is a flaky test — note the
   pass/fail pattern and treat flakiness as a primary classification.

Report the flakiness table (test × run1/run2/run3 × result) in the
classification doc. A test failing every time locally but never on CI is the
**env-specific** signal — the leading hypothesis, not flakiness.

## Phase 2 — Classify each failure (judgment, the core deliverable)

For each of the 4 tests, read the test AND the production code it exercises.
Cite `file:line` for both the assertion and the mechanism. Assign exactly one
classification:

- **real-bug** — the test encodes a correct contract; production code violates it.
  Do NOT delete. Do NOT fix. Mark "real defect, production fix out of scope."
- **env-specific-real** — the test is correct but depends on a real display /
  AppKit session (or a specific host condition) that differs between this host
  and CI's `macos-26` runner; the production behavior is correct and the test
  should be isolated from the host session, not deleted. Investigate *what* host
  condition (e.g. presence of a real `NSScreen`, an active AppKit event loop,
  screen-count assumptions) drives the divergence. Mark "env-specific; pin or
  quarantine, do not delete."
- **fragile-mock** — the assertion depends on internal choreography (call counts,
  ordering, mock wiring) that no longer reflects the implementation, but no real
  behavior is at stake. Candidate for deletion or extraction.
- **stale-contract** — the test asserts an old intended behavior that was
  intentionally changed; the production code is correct and the test is now
  wrong. Candidate for deletion (with the commit/PR that changed the behavior
  cited, if findable in `git log`).
- **flaky** — passes sometimes; the failure is timing/ordering nondeterminism,
  not a fixed bug. Candidate for deletion or stabilization.

For every classification, state the **falsifier**: the observation that would
prove the classification wrong. Then, where the artifact permits, check for it.

Be especially careful with #1 and #3 — `0==1` count assertions are classic
fragile-mock shapes, but they can also be real "the suppression/transaction path
no longer fires" bugs. Distinguish by reading whether the counted thing is a
real user-facing invariant or internal bookkeeping. Read the production method
the count instruments; decide whether the count moving to 0 changes real behavior.

For #2 — a 556pt width delta on a "should not retile" assertion: is the parent
actually retiled (real bug), or does the test set up `cachedWidth` in a way that
the implementation legitimately recomputes (stale/fragile)? Read the retile guard.

For #4 — focus/activation assertions: does the production focus-suppression
branch actually exist and is it reachable the way the test assumes? This one has
the most issues (5) and is the most likely to be a real focus-path regression or
a test that no longer matches the focus model. Read `WMControllerFocusTests.swift`
around 1070-1077 and the production activation path it drives.

## Phase 3 — Act on fragile/valueless tests (deletion)

For each test you classify **fragile-mock**, **stale-contract**, or **flaky**
*and* that does not guard any real behavior: delete it.

- Deletion from a frozen monolith is the sanctioned path — remove the test
  function and any helpers that become dead after removal (confirm they are not
  used elsewhere with grep before deleting a helper).
- Each deletion is its own commit. Plain-English subject, no Conventional Commits.
  Commit body states: the classification, the `file:line` of the removed
  assertion, the production mechanism it instrumented, and why it guarded no
  real behavior. This reasoning is the deliverable — write it carefully.
- If a deletion would remove the *last* coverage of a real path, do not delete;
  instead propose (in the doc) extracting a focused per-behavior replacement and
  leave the original with a `needs-human-review` note.
- For `env-specific-real` and `real-bug`: **do not delete.** Document only.

After all deletions, re-run the affected suites (filtered) to confirm they are
green and that you did not break the build. Then `mise run test:compile` to
confirm the whole test target still compiles (deleting a test can orphan a
helper and break compilation — catch it).

## Phase 4 — Write the classification document

Write `.agents/test-failure-classification.md` (self-contained, per the
durable-document rules — no `/tmp` paths, no host paths, no trace filenames, no
unanchored "current/previous"). For each of the 4 tests: classification, the
assertion + observed value, the production mechanism (`file:line`), the
falsifier you checked, flakiness table, and the action taken (deleted /
documented / needs-human-review). End with a one-paragraph summary of the
green-CI-vs-red-local gap's most likely root cause across the set.

This document must be readable by someone with only the repo and no access to
your machine.

## FENCES

- Touch only files under `Tests/` (deletions), `.agents/` (this plan + the
  classification doc + the baseline seed), and nothing under `Sources/`.
- Do not modify `Sources/` at all. Real-bug findings get recorded, not fixed.
- Do not delete a test you cannot confidently classify; mark it
  `needs-human-review` and leave it.
- Do not push. Commit in this worktree only.
- Do not create a comparison worktree or branch.

## Validation

- After each deletion: re-run the affected suite filtered, then `mise run test:compile`.
- At the end: `mise run test:compile` (whole target compiles), `mise run build`
  (production unaffected — should be a no-op change set), `mise run format:check`,
  `mise run lint`. Fix anything you broke with `mise run fix`.
- Finally re-run `mise run test` once and record the new failure count. The goal
  is not "0 failures at all costs" — it is "remaining failures are real bugs or
  env-specific-reals, documented, and none are fragile tests we chose to keep."

## Commit shape

One commit per deleted test (or per tightly-related group), plain-English
subjects, e.g.:

- "Drop fragile read-count assertion from nonFocusedFrameChangedMatchingLastAppliedFrameDoesNotRelayout"
- "Remove stale-contract no-retile assertion in parentedStandardChildDoesNotRetileNiriParent"

Plus a final commit adding `.agents/test-failure-classification.md` and the
baseline seed if not yet committed:

- "Add pre-existing local test-failure classification"

## Completion token

When done and the validation gates pass, print this exact line on its own:

`TEST_FAILURE_CLASSIFICATION_DONE_<commit-sha-of-last-commit>`

Then stop. Do not push.
