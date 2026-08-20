# Moved window is parked offscreen on its destination workspace while holding focus — Discovery

Scope: a window moved to an adjacent workspace via `moveWindowToWorkspaceDown` /
`moveWindowToWorkspaceUp` can land selected in a column outside the destination
viewport. It is parked offscreen, receives no frame write, and still takes
keyboard focus — so the user sees a different window than the one they moved
while keystrokes go to the moved window.

All file/line references were verified against the Nehir source tree at
`f097f35a` ("Invalidate cached column spans when the monitor set changes
(#198)"). **Re-verify before implementing; line numbers drift.**

---

## TL;DR

- **Symptom (user-confirmed):** moving a window down from workspace 1 to
  workspace 2 switches the visible workspace to 2, focus lands on the moved
  window, but the window drawn on screen is a different one. The moved window is
  parked at the right screen edge.
- **Mechanically confirmed:** the moved window ends up with
  `activeColumnIndex` pointing at its column while `viewOffsetPixels` still
  places the viewport elsewhere, so the column is entirely outside the viewport.
  The layout pass then parks it `layoutTransient(right)` and emits no frame
  write for it, while the focus handoff still grants it focus.
- **Root cause: NOT identified.** Six candidate mechanisms were tested against
  runtime evidence and eliminated (list below). The reveal step that should
  scroll the destination viewport provably works in isolation (CI-verified) and
  has been observed working at runtime on the same code path.
- **Status:** 🟡 **Open / intermittent.** The defect is timing-dependent: it
  reproduces most of the time with runtime trace capture **off**, and did not
  reproduce in repeated attempts with capture **on**. Instrumentation perturbs
  it.

## Symptom and confirmed reproduction

Reported and reproduced by the user with an unmodified release build:

1. A TextEdit window is on workspace 1.
2. Press the hotkey bound to `moveWindowToWorkspaceDown`.
3. The visible workspace switches to 2 (so `[focus] followsWindowToMonitor =
   true` is working).
4. The window visible on screen is **not** the moved TextEdit window.
5. Keyboard input goes to the moved TextEdit window, which is not visible.

Reproduces "most of the time" when trace capture is off. Does not require a
Nehir-fullscreen window on the destination, does not require the moved app to
have multiple windows, and is not specific to TextEdit.

Topology in the confirmed reproduction: workspaces 1, 2 and 3 all assigned to
the same physical display (`displayId=2`, a 2560x1440 monitor with a 2560-wide
working frame). Destination workspace 2 held four columns.

## Mechanically confirmed state at failure

Captured from a runtime trace of a failing move (values inlined; the trace file
itself is machine-local and ephemeral).

Destination workspace 2 after the transfer:

```
columns=4
column x positions: c0=0.0  c1=1170.0  c2=2340.0  c3=3510.0   (each cached=1150.0, gap=20)
activeColumnIndex=3
currentOffset=-3530.0   targetOffset=-3530.0
currentViewStart=-20.0  targetViewStart=-20.0
```

The moved window is the sole window of column `c3`. Its recorded node state:

```
w6531:selected  cur=2559,50,1150,1310  hidden:right
```

Model state for the moved window at the post-layout focus handoff:

```
targetVisible=true  stillAssigned=true  willFocus=true
hiddenState=HiddenState(reason: layoutTransient(HideSide.right),
                        referenceMonitorId: displayId 2)
```

Layout diff for the destination workspace in the same transition:

```
frameUpdates=[]
revealUpdates=["5520:120,50", "50:1290,50"]
hiddenTokens=[6531, 59]
pendingReveal=[5520, 50]
```

So: the moved window (`6531`) is in `hiddenTokens` and receives **no frame
write**, while the two windows already resident on workspace 2 (`5520`, `50`)
are revealed at on-screen positions. Those are the windows the user sees.
`confirmedFocus` remained on the moved window throughout.

### Why the window is outside the viewport

`viewPosPixels` is `columnX(activeColumnIndex) + viewOffsetPixels`
(`Sources/Nehir/Core/Layout/Niri/ViewportState+Animation.swift:11-14`). With
`activeColumnIndex=3` and offset `-3530`:

```
3510.0 + (-3530.0) = -20.0
```

The viewport therefore spans roughly `-20 … 2540`, while column 3 spans
`3510 … 4660` — about 970pt beyond the right edge. `currentViewStart ==
targetViewStart` means **no scroll was scheduled** toward it.

`columnVisibility`
(`Sources/Nehir/Core/Layout/Niri/ViewportState+Geometry.swift:729-757`)
classifies that column `.parked(.maximum)`: `columnStart (3510) >= viewportEnd
(2540) - preParkMargin (16)`. Evaluated for viewport widths 2560, 2520 and 2320,
the result is `.parked(.maximum)` in every case.

### The offset value itself is correct by design

`ensureSelectionVisible`
(`Sources/Nehir/Core/Layout/Niri/NiriNavigation.swift:174-249`) performs two
steps. The first is a deliberately view-neutral rebase
(`NiriNavigation.swift:215-226`):

```swift
let offsetDelta = oldActivePos - newActivePos
state.viewOffsetPixels.offset(delta: Double(offsetDelta))
state.activeColumnIndex = targetIdx
```

Reproducing that arithmetic from the recorded pre-transfer destination state
(`activeColumnIndex=2`, offset `-2360.0`, `viewStart=-20.0`):

```
offsetDelta   = 2340.0 - 3510.0 = -1170.0
new offset    = -2360.0 + (-1170.0) = -3530.0
new viewStart = 3510.0 + (-3530.0) = -20.0
```

This matches the observed failure state exactly. `-3530` is therefore **not
corruption** — it is the rebase correctly preserving `viewStart` while
retargeting the index. The rebase is view-neutral by intent, which makes the
second step (the reveal) load-bearing: it is the only thing that can move the
viewport onto the moved window's column.

## The reveal works in isolation

`Tests/NehirTests/MovedWindowRevealAfterWorkspaceTransferTests.swift` (added on
branch `la/moved-window-reveal-diagnostic`, not yet merged to `main`)
reconstructs the failure geometry (four 1150pt columns, 20pt gap, 2560pt
viewport, `activeColumnIndex=3`, `viewOffsetPixels=-3530`) and asserts the
reveal behaviour. All five cases **pass** in CI on `macos-26`:

- `rebasingActiveColumnPreservesViewStart`
- `movedColumnIsParkedBeforeReveal`
- `revealsMovedColumnParkedOutsideDestinationViewport`
- `schedulesScrollTowardMovedColumn`
- `revealsMovedColumnEvenWhenViewportIsScrollLocked`

Source analysis agrees. For column 3 in that geometry,
`computeSnapGrid`/`viewportStartBounds`
(`ViewportState+Geometry.swift:600-620`, `:670-712`) yield:

```
viewportStartBounds = [-2482.5, 4582.5]         (nothing is clamped away)
snap offsets: leftEdge=3490.0  rightEdge=2120.0  center=2805.0
targetOffset = snapOffset - activeX(3510):
  leftEdge  ->   -20.0
  rightEdge -> -1390.0
  center    ->  -705.0
```

Every candidate differs from the live target (`-3530`) by far more than the
`pixel = 0.5` tolerance in the final guard
(`Sources/Nehir/Core/Layout/Niri/NiriLayoutEngine+ViewportCommands.swift:190-193`),
so `animateToOffset` is called and `true` returned. The scroll-lock guard
(`:134-136`) explicitly permits a `.parked` target. `isFFM` is `false` at this
call site, and the snap-point set is non-empty.

**Conclusion:** no path through `scrollToReveal` leaves the viewport at `-3530`
for this state.

### And it has been observed working at runtime

A later trace captured a move with the same shape that **succeeded**
(`movedColumnIndex=2`, `stateActiveColumnIndex=0` going in — i.e. the rebase had
real work to do):

```
reveal_after:  viewStart=-19.26          targetViewStart=1150.0
pre_commit:    viewOffsetCurrent=-2340.84  viewOffsetTarget=-1190.0
               viewStart=-0.82           targetViewStart=1150.0
```

The reveal set a target, the animation registered, the display-link driver
sampled it, and the target survived the session-patch commit. This is the
known-good reference for the failing path.

### The failing path is the minority case

Across eight instrumented moves in one trace, seven had `stateActiveColumnIndex`
**already equal** to the moved window's column index on entry to
`ensureSelectionVisible` — the rebase was a no-op and the viewport already
showed the destination column, so nothing needed revealing. Only one move had
the mismatched shape that requires a real scroll.

The failure therefore requires `activeColumnIndex != movedColumnIndex` at reveal
time, and even then usually succeeds. This explains the intermittency: most
moves never exercise the vulnerable path.

## Candidate mechanisms eliminated

Each was tested against runtime evidence or source arithmetic and does **not**
explain the failure.

| # | Candidate | Why eliminated |
|---|---|---|
| 1 | A Nehir-fullscreen window on the destination occludes the moved window (`effectiveViewportWidth` ignores `sizingMode`) | The confirmed reproduction has no fullscreen window anywhere. Remains a separate real finding, related to issue #69. |
| 2 | The moved window misses the z-order raise pass (it is in neither `restoreChanges` nor `.show`, so absent from `visibleJobs`) | Real gap, and the raise genuinely does not cover a window transferred from a *visible* workspace. But instrumentation shows `diff.focusedFrame` is `nil` for a hidden window (`NiriLayoutHandler.swift:1239-1242`), so the added raise never fires here — and adding it did not fix the symptom. |
| 3 | `prepareMovedWindowTargetViewport`'s guards reject, so the reveal never runs | Instrumented: `enginePresent=true findNodeOK=true findColumnInTargetOK=true revealRequested=true` on every observed move. `findColumn` is synchronous tree-walking (`NiriLayoutEngine.swift:395-400`) with no timing dependency. |
| 4 | The stale-selection guard in `applySessionPatch` reverts the rebase (it restores `activeColumnIndex` from live state while preserving `viewOffsetPixels`) | Instrumented across two traces / 128 patches: fired **once**, on the source workspace, with every value identical (`incomingIdx=3 liveIdx=3 committedIdx=3`, offsets all `-1190`). Harmless. |
| 5 | `stopScrollAnimation(for: sourceMonitor.displayId)` in `finishWorkspaceMove` destroys the destination's freshly-scheduled animation, because `scrollAnimationByDisplay` holds one workspace per display and all workspaces share display 2 | Instrumented every registry mutation: `overwrites=false` on every `REGISTER`, every `STOP` removed the workspace that registered it, and the source-monitor stop consistently reported `removed=none`. The display-key collision does not occur in practice. |
| 6 | Frame changes discarded by `dropStaleFrames` while an animation is registered (`LayoutRefreshController.swift:4409-4418`) | Observed firing, but only during *successful* animated reveals (`DROP_STALE_FRAMES ws=3 dropped=3`), which is its documented purpose — the display-link driver owns frames while animating. In the failing trace no animation was registered at all. |

## What the evidence now says

In the failing run the scroll was **never scheduled** — not scheduled and then
destroyed. `currentViewStart == targetViewStart == -20.0` means no target was
ever set, and no animation was registered.

That is difficult to reconcile with `scrollToReveal` provably scheduling a
scroll for that exact state, and with the same path observed succeeding at
runtime. The remaining possibilities, none yet tested:

- **Motion policy.** `ensureSelectionVisible` receives
  `controller.motionPolicy.snapshot()`. If that resolves such that
  `animateToOffset` applies the offset instantly rather than scheduling an
  animation, the reveal could complete without a registered animation and be
  overwritten by a later write. No instrumentation has recorded the motion
  snapshot at this call site.
- **A different column geometry at failure time.** The reveal is a legitimate
  no-op if `columnVisibility` returns `.fullyVisible`. The recorded failure
  geometry computes to `.parked`, but the widths at the exact moment
  `ensureSelectionVisible` ran were not captured independently of the
  post-transfer dump.
- **The computed state discarded between reveal and commit.**
  `prepareMovedWindowTargetViewport` mutates a local `targetState` and commits
  via `applySessionPatch` (`WorkspaceNavigationHandler.swift:141-145`); the
  observed `patch_committed` samples show `matches=true`, but only from
  succeeding runs.

## Reproduction guidance for the next attempt

- The vulnerable path needs the destination viewport **not** already resting on
  the column the moved window will occupy. Concretely: switch to the destination
  workspace, scroll to a different column, switch back, then move a window in.
- Runtime trace capture suppresses the defect. A lighter-weight permanent
  diagnostic (a few fields on an existing trace event) is more likely to survive
  than the heavyweight probe layer used here.
- The single most diagnostic datum is whether an animation is registered for the
  destination workspace immediately after `ensureSelectionVisible` returns, plus
  the motion snapshot that call received.

## Related work

- Issue #69 (`toggleFullscreen` state persisting across focus changes) is a
  distinct defect uncovered while investigating this one. `sizingMode ==
  .fullscreen` is cleared only by re-toggling: the two sites that assign
  `.normal`
  (`Sources/Nehir/Core/Layout/Niri/NiriLayoutEngine+Sizing.swift:937-939`,
  `:999-1001`) are both guarded by `if window.sizingMode == .maximized`. A
  separate finding, not a cause of this bug.
- The z-order gap from candidate 2 is real on its own terms: a window
  transferred from a visible workspace produces no visibility change, so it is
  absent from the raise pass that force-orders restored windows above. It does
  not fix this bug and should not be described as doing so.

## Status

- Symptom: **confirmed by the user in their real reproduction.**
- Failure state: **observed** in a runtime trace, with the arithmetic
  independently reproduced from the recorded values.
- Root cause: **under investigation.** Six candidates eliminated; no confirmed
  mechanism.
- Fix: **none proposed.** No change should be described as fixing this until a
  mechanism is identified and the user confirms the behaviour in their real
  reproduction.
