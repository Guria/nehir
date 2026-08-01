# PR #193: Ghostty tab identity and overlay-close focus fixes

**Status:** completed — shipped on `main` in commits `90f47c04` through
`8a245ffc`, merged 2026-07-31 via PR #193, contained in
`v0.6.0-rc.43`. Recorded in `completed/` on 2026-08-01.

PR #193 combined the fixes for Nehir issues #179 and #191 with the follow-up
focus, lifecycle, pointer, diagnostics, regression-test, and qutebrowser
workspace-bar work developed during runtime validation. Issues #179 and #191
were closed automatically when the PR merged on 2026-07-31.

## Commits on `main`

`main` contains every commit below; each is an ancestor of `8a245ffc` and
the first containing tag is `v0.6.0-rc.43`.

| Commit | Subject | Landed responsibility |
| --- | --- | --- |
| `90f47c04` | Stop admitting non-window parented surfaces as managed windows | Shared user-addressable AX-surface predicate; Finder inline editor remains unmanaged. |
| `acbebfbd` | Carry window identity through tab churn and steady the overlay-close focus | Deferred destroy correlation, tab identity rekeying, explicit confirmation classification, recognized overlay identity, close anchor. |
| `ca152b28` | Stabilize focus arbitration around overlays and window teardown | Multi-pair replacement convergence, liveness audit, overlay lifecycle, pointer intent, same-app succession, diagnostics, regression suites. |
| `3fc530fb` | Show qutebrowser windows in the workspace bar | Top-level qutebrowser `AXDialog` exception and workspace-bar projection. |
| `b0bca2f6` | Harden overlay lifecycle and focus recovery | Bounded destroy verification, focused admission without a WindowServer record, deterministic lifecycle tests and cleanup. |
| `905aaadd` | Harden pointer classification and trace retention | Injectable Notification Center bundle lookup, WindowServer level boundaries, shared bounded runtime-trace storage. |
| `8a245ffc` | Match qutebrowser bundle identifiers case-insensitively | Named case-insensitive qutebrowser bundle comparison and regression coverage. |

The PR branch commit ids shown by GitHub differ because the PR was rebased onto
`main`; the table records the commits that actually exist on `main`.

## Landed behavior

### Finder child surfaces (#179)

Admission and workspace-bar projection now share
`WindowRuleEngine.presentsAsUserAddressableAXWindowSurface`. A parented surface
whose successful AX facts identify a non-window role, including Finder's inline
rename `AXTextField`, is unmanaged. Failed AX fact retrieval retains the
managed-floating fallback. The user confirmed that Finder context-menu rename
remains editable with Nehir running.

### Ghostty tab identity (#191)

A deferred destroy that is confirmed dead now enters the same
managed-replacement funnel as synchronous teardown. Compatible destroy/create
pairs rekey the existing entry rather than deleting and reinserting its layout
column. Pairing is sequence ordered and supports several pairs per burst;
one-sided bursts wait for pending create/destroy pipelines, and a per-pid
liveness audit removes windows whose destroy notification was lost. The user
confirmed that switching, creating, and closing Ghostty tabs preserves column
identity and width and no longer accumulates phantom columns requiring a
restart.

### Quick Terminal close, pointer intent, and same-app succession

Recognized overlay window ids and their ordered-in/destroy observations define
the overlay lifecycle. Cause-less restore activations during the pre-destroy
phase cannot drag parked follow or viewport reveal away from the selected
window; destroy-time correction uses the newest explicit managed confirmation.
Pointer-confirmed focus can be adopted without issuing a second native focus
request. Same-app successor focus is held until AX enumeration establishes
whether the predecessor is still alive, distinguishing an ordinary switch from
a close-selected successor.

The user confirmed these real reproductions before merge:

- Quick Terminal open → Cmd+N → close preserves focus and viewport;
- closing a window whose app immediately focuses an off-screen same-app window
  does not drag the viewport there;
- ordinary same-app window switching and browser profile switching remain
  functional.

### qutebrowser workspace-bar projection

A level-zero, unparented qutebrowser `AXDialog` is treated as a top-level
user-addressable surface, including both raw WindowServer parent `0` and
normalized `nil`; nonzero-parent child dialogs remain excluded. Bundle matching
is case-insensitive. The user confirmed that a normal qutebrowser window appears
in the workspace bar without a custom rule.

## Deviations from the planning documents

- The planned 250 ms cross-pid deferred-activation queue did not ship. The
  landed code confirms native focus reality while suppressing only harmful
  parked-follow/reveal effects during the recognized overlay's pre-destroy
  lifecycle. No replay payload or new activation deadline was added.
- The early Quick Terminal discovery proposed a generic 500–1000 ms recent
  overlay-evidence map. The landed lifecycle is narrower and derives from
  recognized window identity, ordered-in state, recognized focus, and destroy;
  app menus and arbitrary non-managed surfaces cannot manufacture overlay
  evidence.
- The Finder discovery proposed both rejecting non-window child surfaces and a
  broader same-application transient-focus fronting policy. Only the shared
  surface predicate shipped; it removed the causative layout refresh and was
  sufficient for #179.
- The tab-identity implementation expanded beyond the initial deferred-destroy
  funnel proposal with greedy multi-pair matching, burst extension, liveness
  audit, bounded teardown verification, and explicit cleanup.
- The qutebrowser exception was added during runtime review after the normal
  browser surface was observed as an unparented level-zero `AXDialog`; it was not
  part of the original Ghostty/Finder scope.

## Work intentionally not shipped

- Rapid Ghostty tab bursts can still show a brief transient dance before the
  layout settles. The #191 release note records this accepted residual.
- Window-menu same-app picks can still be redirected by generic non-managed
  focus evidence; see
  [`../discovery/20260729-window-menu-same-app-pick-redirected-to-other-apps-stable-window.md`](../discovery/20260729-window-menu-same-app-pick-redirected-to-other-apps-stable-window.md).
- Cross-app successor selection after an ordinary managed-window close remains a
  separate policy issue; see
  [`../discovery/20260709-window-close-successor-app-activation-reveals-far-parked-column.md`](../discovery/20260709-window-close-successor-app-activation-reveals-far-parked-column.md).
- Minimal-displacement targeting for insertion relayout was not changed; see
  [`../discovery/20260801-insertion-relayout-lacks-minimal-displacement-targeting.md`](../discovery/20260801-insertion-relayout-lacks-minimal-displacement-targeting.md).
- The general `.springInFlight` completion obligation remains in
  [`../discovery/20260728-preserve-active-viewport-can-strand-confirmed-focus-offscreen.md`](../discovery/20260728-preserve-active-viewport-can-strand-confirmed-focus-offscreen.md).

## Release notes and attribution

Four patch changesets shipped:

- `.changeset/20260729134719-switching-creating-and-closing-ghostty-tabs-no-l.md`
  — #191; contributor `dagrlx`.
- `.changeset/20260729134729-closing-the-ghostty-quick-terminal-no-longer-scr.md`
  — Quick Terminal, same-app close, and browser profile focus; no contributor
  entry.
- `.changeset/20260729134729-renaming-a-file-from-finder-s-context-menu-works.md`
  — #179; contributor `dagrlx`.
- `.changeset/20260731175114-normal-qutebrowser-windows-now-appear-in-nehir-s.md`
  — qutebrowser workspace-bar projection; no contributor entry.

`dagrlx` reported both #179 and #191. Runtime decisions and confirmations were
provided by Aleksei Gurianov during the instrumented reproductions.

## Tests that landed

- `Tests/NehirTests/AXEventHandlerTests.swift`
- `Tests/NehirTests/FocusedCreateStabilizationTests.swift`
- `Tests/NehirTests/LayoutPlanTestSupport.swift`
- `Tests/NehirTests/ManagedReplacementFocusReconciliationTests.swift`
- `Tests/NehirTests/QuickTerminalCloseAnchorTests.swift`
- `Tests/NehirTests/QuickTerminalPointerIntentTests.swift`
- `Tests/NehirTests/QuickTerminalStartupLifecycleTests.swift`
- `Tests/NehirTests/QutebrowserWorkspaceBarProjectionTests.swift`
- `Tests/NehirTests/SameAppCloseFocusSuccessionTests.swift`
- `Tests/NehirTests/TerminatedAppStatePruningTests.swift`
- `Tests/NehirTests/WindowServerPointerOcclusionTests.swift`
- `Tests/NehirTests/WMControllerFocusTests.swift`

## Gate result

The final PR #193 GitHub checks passed:

- `mise run test` — GitHub check `Swift tests`, passed in 3m38s;
- SwiftLint and SwiftFormat — GitHub check `SwiftLint + SwiftFormat`, passed in
  43s;
- CodeRabbit review — passed with no actionable comments.

## Companion records

- [`20260729-finder-inline-rename-cancelled-by-focus-recovery.md`](20260729-finder-inline-rename-cancelled-by-focus-recovery.md)
- [`20260729-ghostty-tab-switch-destroy-bypasses-managed-replacement-burst.md`](20260729-ghostty-tab-switch-destroy-bypasses-managed-replacement-burst.md)
- [`20260726-browser-reactivation-overrides-new-ghostty-selection.md`](20260726-browser-reactivation-overrides-new-ghostty-selection.md)
- [`20260728-overlay-close-viewport-churn-competing-motion-actors.md`](20260728-overlay-close-viewport-churn-competing-motion-actors.md)
- [`20260728-defer-causeless-restore-during-overlay-close.md`](20260728-defer-causeless-restore-during-overlay-close.md)
- [`20260713-same-app-close-successor-reveals-before-actionable-removal.md`](20260713-same-app-close-successor-reveals-before-actionable-removal.md)
- [`20260702-quick-terminal-close-reveals-managed-ghostty-column.md`](20260702-quick-terminal-close-reveals-managed-ghostty-column.md)
