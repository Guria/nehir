# Pre-existing local test failures on main — baseline evidence

Captured from a full `mise run test` run on a pristine `main` worktree at
commit `afc68733` (the exact commit CI reports green). This is the starting
evidence for classification. It is deliberately self-contained: no machine-local
paths, no log filenames.

CI status at this commit (guria/nehir, workflow `ci.yml`, branch `main`):
the "Update instructions" run for `afc68733` completed `success` (~3m24s),
including the `Run tests` step (`mise run test`). So these assertions pass on
CI's `macos-26` runner but fail locally.

## Run summary

```text
✘ Test run with 1510 tests in 138 suites failed after 33.945 seconds with 10 issues.
```

The run completed (not a crash/SIGTRAP). All 10 issues are `Expectation failed:`
assertion mismatches across 3 suites, 4 tests.

## Failing tests and observed mismatches

### AXEventHandlerTests (suite: 4 issues, 7.108s)

`nonFocusedFrameChangedMatchingLastAppliedFrameDoesNotRelayout` — 2 issues:
- `AXEventHandlerTests.swift:5100` — `Expectation failed: (observedReadCount → 0) == 1`
- `AXEventHandlerTests.swift:5103` — `Expectation failed: (controller.axEventHandler.debugCounters.geometryRelayoutsSuppressedForOwnFrameWrites → 0) == 1`

`parentedStandardChildDoesNotRetileNiriParent` — 2 issues:
- `AXEventHandlerTests.swift:9763` — `Expectation failed: (abs(updatedParentColumn.cachedWidth - originalParentCachedWidth) → 556.0) < 0.5`
- `AXEventHandlerTests.swift:9790` — same, with `finalParentColumn`

### LayoutRefreshControllerTests (suite: 1 issue, 1.106s)

`executeLayoutPlanShowWithCachedVisibleFrameClearsHiddenStateWithoutRevealTransaction` — 1 issue:
- `LayoutRefreshControllerTests.swift:2079` — `Expectation failed: (attemptCount → 1) == 0`

### WMControllerFocusTests (suite: 5 issues, 1.259s)

`genericUnmanagedFocusDoesNotSuppressInactiveWorkspaceActivation` — 5 issues:
- `WMControllerFocusTests.swift:1070` — `activeWorkspace(on: monitorId)?.id → 70471001-... == workspaceTwo → FB746DEE-...`
- `WMControllerFocusTests.swift:1071` — `focusedHandle → nil == inactiveHandle → Nehir.WindowHandle`
- `WMControllerFocusTests.swift:1075` — same active-workspace mismatch
- `WMControllerFocusTests.swift:1076` — same focusedHandle mismatch
- `WMControllerFocusTests.swift:1077` — `currentBorderTarget()?.token → nil == inactiveToken → WindowToken(pid: 74001, windowId: 613)`

## What this rules out

- Not caused by the focus-signal tracer (separate branch): these fail on clean
  main with no tracer present.
- Not the documented `swiftpm-testing-helper` SIGTRAP: the run completed with
  assertion issues, not a process crash.
- Not build/compile breakage: `mise run build` is green on this commit.

## Open questions for classification

- Are these deterministic on repeated local runs (flaky) or stable (env-specific)?
- Do they depend on the host having a real display/AppKit session vs CI's headless runner?
- Do the assertions encode a real contract or fragile mock choreography / internals?
- For each: keep, rewrite to per-behavior, or delete as no-value/fragile?
