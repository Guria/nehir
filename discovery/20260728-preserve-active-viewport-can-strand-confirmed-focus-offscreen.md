# `preserveActiveViewport` can strand confirmed focus outside the viewport

**Status:** actionable for `.springInFlight`; source-confirmed policy boundary for `.gesture`, `.alreadyConfirmedFocusedWindowChanged`, and `.closeRecoveryPin`

Verified against the main Nehir source tree on 2026-07-28. Runtime evidence is inlined below; no machine-local trace is required to follow the finding.

## Summary

`AXEventHandler.handleManagedAppActivation` commits managed focus before deciding whether the viewport reveal may run. Four preservation reasons are collapsed into one Boolean, `preserveActiveViewport`; every non-`.none` reason bypasses `scrollToReveal` completely.

That is not merely a theoretical gap. A retained capture contains this exact sequence:

1. a spring was already moving the viewport toward columns 4–5;
2. a window in column 0 became the confirmed managed focus;
3. its only confirmation pass used `preserveActiveViewportReason=spring_in_flight` and skipped the reveal;
4. the spring continued, classified the confirmed window as `visibleToHidden bucket=offscreen`, and settled with that window `hidden:left`; and
5. no later confirmation arrived to repair the viewport.

The fundamental defect is therefore not inside `scrollToReveal`. The higher-level guard treats “do not interrupt this viewport operation now” as “this accepted focus never needs a reveal,” with no deferred visibility obligation and no post-operation reconciliation.

The four reasons must not be fixed by one blanket “parked beats preserve” rule. Their contracts differ:

- a live gesture should not be fought synchronously, but a still-confirmed parked target needs a post-gesture reconciliation;
- a spring whose destination will park the newly confirmed target must be retargeted or followed by a guaranteed reveal;
- an already-confirmed duplicate must continue to respect a deliberate manual scroll away from the focused window, while not discarding unfinished reveal work from the same focus episode; and
- close recovery should normally reject or redirect a bad parked successor before confirmation rather than reveal it and abandon the stable close anchor.

## Source mechanism

### Focus is committed before preservation is evaluated

`handleManagedAppActivation` samples whether the token was already confirmed at `Sources/Nehir/Core/Controller/AXEventHandler.swift:4628`:

```swift
let wasAlreadyConfirmedFocus = controller.workspaceManager.confirmedManagedFocusToken == entry.token
```

It then commits the confirmation at `AXEventHandler.swift:4635-4643`:

```swift
if shouldConfirmRequest {
    _ = controller.workspaceManager.confirmManagedFocus(
        entry.token,
        in: wsId,
        onMonitor: monitorId,
        appFullscreen: appFullscreen,
        activateWorkspaceOnMonitor: shouldActivateWorkspace
    )
```

Only after that does it inspect viewport state and select a preservation reason. This ordering matters when reading traces: `ax_focus_confirm_before_activate` is emitted after `confirmManagedFocus`, so its generic `confirmedFocus=` snapshot already contains the new token. The authoritative field for deduplication is the separately captured `wasAlreadyConfirmedFocus=` value.

### Preservation is a priority-ordered, unconditional gate

The reasons are declared at `AXEventHandler.swift:37-47`; every case except `.none` returns `shouldPreserve=true`.

The selection at `AXEventHandler.swift:4753-4765` is priority ordered:

| Priority | Reason | Condition |
| --- | --- | --- |
| 1 | `.gesture` | `state.viewOffsetPixels.isGesture` |
| 2 | `.springInFlight` | the offset is animating and more than one device pixel from its target (`:4727-4729`) |
| 3 | `.alreadyConfirmedFocusedWindowChanged` | the token was already confirmed and `source == .focusedWindowChanged` |
| 4 | `.closeRecoveryPin` | any same-app close-recovery viewport pin is armed (`:4730-4751`) |
| — | `.none` | none of the above |

`focusedWindowChanged` is the authoritative window-level activation source (`Sources/Nehir/Core/Controller/ServiceLifecycleManager.swift:10-17`).

### Any preservation reason bypasses the engine

The reveal block is entered only under `!preserveActiveViewport` at `AXEventHandler.swift:4817-4821`. The call to `engine.scrollToReveal` is at `:4855-4863`. Otherwise the handler emits `ax_focus_confirm_reveal_skipped` with `skipReason=preserve_active_viewport` at `:4874-4886`.

Consequently, none of these can affect a preserved pass:

- `RevealTrigger`;
- viewport scroll-lock policy;
- reveal style;
- parked/clipped/fully-visible classification; or
- any rule inside `scrollToReveal`.

The function is not called.

If entered, the engine would evaluate visibility against the viewport's **target** position: `ViewportSnapContext.currentViewStart(in:)` returns `state.targetViewPosPixels(...)` (`Sources/Nehir/Core/Layout/Niri/ViewportState+Geometry.swift:82-84`), and `scrollToReveal` classifies the target at `Sources/Nehir/Core/Layout/Niri/NiriLayoutEngine+ViewportCommands.swift:84-90`. That is precisely the information needed to distinguish “the current spring already lands on this focus target” from “the current spring will carry this focus target off-screen.” The higher-level Boolean gate prevents that distinction.

## Capture A: the scroll-lock reproduction does not prove a preserve-only failure

The capture that exposed this follow-up had five 50%-width columns and a viewport settled at `viewStart=1011.0`. Window `58013:10371` was in column 4 at strip position `x=4068.0`.

Its first confirmation pass was:

```text
reason=ax_focus_confirm_before_activate
  token=WindowToken(pid: 58013, windowId: 10371)
  wasAlreadyConfirmedFocus=false
  preserveActiveViewport=false
  preserveActiveViewportReason=none
  isGesture=false
  wasAnimating=false
  currentViewStart=1011.0
  targetViewStart=1011.0

reason=ax_focus_confirm_reveal_candidate
  token=WindowToken(pid: 58013, windowId: 10371)
  columnIndex=4
  locked=true
  visibility=parked(maximum)
  viewStart=1011.0
  closest=3045.0:rightEdge

reason=ax_focus_confirm_reveal_result
  token=WindowToken(pid: 58013, windowId: 10371)
  didReveal=false
  currentViewStart=1011.0
  targetViewStart=1011.0
```

A duplicate window-level confirmation followed about 27 ms later:

```text
reason=ax_focus_confirm_before_activate
  token=WindowToken(pid: 58013, windowId: 10371)
  wasAlreadyConfirmedFocus=true
  preserveActiveViewport=true
  preserveActiveViewportReason=already_confirmed_focused_window_changed
  currentViewStart=1011.0
  targetViewStart=1011.0

reason=ax_focus_confirm_reveal_skipped
  token=WindowToken(pid: 58013, windowId: 10371)
  skipReason=preserve_active_viewport
  preserveActiveViewportReason=already_confirmed_focused_window_changed
```

This sequence proves the gate is upstream of the engine, but it does **not** prove that deduplication caused this occurrence. The first pass reached `scrollToReveal`; its `didReveal=false` result was the scroll-lock failure documented in [`20260728-scroll-lock-suppresses-hotkey-focus-reveal.md`](20260728-scroll-lock-suppresses-hotkey-focus-reveal.md). The second pass was a true duplicate and did not change the outcome.

It follows that a lower-level parked-target repair can solve this exact capture, because the first non-preserved pass exists. A different capture is required to prove that preservation can consume every opportunity to reveal.

## Capture B: `.springInFlight` consumed the only reveal opportunity

That stronger capture already exists.

### Initial topology and spring

One active workspace held eight columns, each 1011 pt wide, under a 2040 pt viewport. The viewport was already springing with column 5 active:

```text
reason=scroll_animation_start
  columns=8
  activeColumnIndex=5
  currentViewStart=2875.8
  targetViewStart=4062.0
  animating=true
  confirmedFocus=nil
```

The destination `viewStart=4062.0` shows columns around indices 4–5. Window `53999:33409` belonged to column 0.

### The only focus-confirm pass was preserved

An app-level activation for `53999:33409` arrived while the spring was in flight:

```text
reason=close_recovery_activation_gate
  token=WindowToken(pid: 53999, windowId: 33409)
  source=workspaceDidActivateApplication
  isWorkspaceActive=true

reason=ax_focus_confirm_before_activate
  token=WindowToken(pid: 53999, windowId: 33409)
  wasAlreadyConfirmedFocus=false
  preserveActiveViewport=true
  preserveActiveViewportReason=spring_in_flight
  isGesture=false
  wasAnimating=true
  currentViewStart=3755.5
  targetViewStart=4062.0
  activeColumnIndex=5
  confirmedFocus=WindowToken(pid: 53999, windowId: 33409)

reason=ax_focus_confirm_reveal_skipped
  token=WindowToken(pid: 53999, windowId: 33409)
  skipReason=preserve_active_viewport
  preserveActiveViewportReason=spring_in_flight
  animating=true
```

The anchor-preserving rebase temporarily changed offset bookkeeping around the newly selected column, but the follow-up relayout preserved the same physical spring destination:

```text
reason=ax_focus_confirm_request_relayout
  activeColumnIndex=0
  currentViewStart=3831.4
  targetViewStart=4062.0
  confirmedFocus=WindowToken(pid: 53999, windowId: 33409)
```

No `ax_focus_confirm_reveal_candidate` or `ax_focus_confirm_reveal_result` existed for this token, and no later `ax_focus_confirm_before_activate` arrived for it in the capture.

### The spring carried confirmed focus off-screen and settled there

As the spring approached its destination, the frame classifier recorded the confirmed window leaving the viewport:

```text
reason=spring_frame_classification
  token=WindowToken(pid: 53999, windowId: 33409)
  frameSource=currentSpring
  visibilityClass=visibleToHidden
  bucket=offscreen
  hiddenSide=left
  currentFrame={{-1010.0,7.0},{1011.0,1251.0}}
  viewport={{8.0,7.0},{2040.0,1251.0}}
  currentViewStart=3971.6
  targetViewStart=4062.0
  selectedNode=<window 33409>
  confirmedFocus=WindowToken(pid: 53999, windowId: 33409)
```

The spring then stopped without any focus-reveal reconciliation:

```text
reason=scroll_animation_stop
  activeColumnIndex=0
  currentViewStart=4062.0
  targetViewStart=4062.0
  animating=false
  selectedNode=<window 33409>
  confirmedFocus=WindowToken(pid: 53999, windowId: 33409)
  window 33409 hidden=left
```

This is the required preserve-only ordering. The target received one accepted confirmation, that pass was suppressed by `.springInFlight`, no duplicate arrived, and the viewport settled where the confirmed window was completely outside it.

It also disproves a deduplication-only repair: there was no duplicate for `.alreadyConfirmedFocusedWindowChanged` to “pick up” the missed work.

## Existing tests encode both sides of the policy conflict

### A genuine in-flight spring is intentionally preserved

`Tests/NehirTests/AXEventHandlerTests.swift:1007-1106` constructs a real, unconverged spring, confirms focus on a different column, and asserts that the spring remains active and its visual trajectory is preserved. The test verifies bookkeeping and confirmed focus, but it does not assert that the newly confirmed target is visible at the spring destination.

That test captures the legitimate half of the contract: a focus echo must not gratuitously cancel a useful spring. It needs to be split by destination visibility rather than simply deleted.

### An already-confirmed parked target is intentionally not revealed

`AXEventHandlerTests.swift:1902-2002` seeds `confirmedManagedFocusToken`, manually parks that focused column off-screen, sends another authoritative `focusedWindowChanged`, and asserts that the visual viewport does not move back.

This is an important compatibility boundary. Users may deliberately scroll away from the still-focused window; token equality plus parked visibility is not sufficient reason to snap back. A blanket “parked overrides `.alreadyConfirmedFocusedWindowChanged`” change would intentionally break this test and the behavior it protects.

## Current production ordering narrows the `alreadyConfirmed` risk

The present source has one production call to `WorkspaceManager.confirmManagedFocus`, inside `handleManagedAppActivation` at `AXEventHandler.swift:4637`. The production callers of `handleManagedAppActivation` pass `confirmRequest: true` at `:4115-4122`, `:4295-4302`, and `:4528-4535`.

Because `wasAlreadyConfirmedFocus` is sampled before that call, a freshly observed token cannot normally enter its first `handleManagedAppActivation` invocation with `.alreadyConfirmedFocusedWindowChanged` solely because this same invocation confirmed it. It reaches that reason only when:

- it was genuinely confirmed before this invocation (for example, the user scrolled away while focus stayed on that window); or
- an earlier invocation already committed the token but failed to complete the desired viewport work, after which an authoritative duplicate arrived.

The second case is the dangerous one, but the spring capture shows that waiting for a duplicate is not a complete recovery strategy.

## 5-Why root-cause analysis

### Why 1: why did input remain focused in an invisible window?

Because the accepted focus token was allowed to become and remain fully outside the viewport.

### Why 2: why was it not revealed?

Because the focus-confirm reveal block never ran.

### Why 3: why did the block not run?

Because `.springInFlight` made `preserveActiveViewport=true`; the same unconditional gate also applies to gesture, already-confirmed deduplication, and close-recovery pins.

### Why 4: why can preservation outlive its legitimate purpose?

Because the Boolean records only whether the viewport should be left alone **at that instant**. It does not record whether the newly confirmed target is already covered by the gesture/spring destination or needs a reveal after preservation ends.

### Why 5: why is there no later correction?

Because focus confirmation and focus visibility are not treated as a completion contract. Once `confirmManagedFocus` succeeds, a skipped reveal creates no durable obligation keyed to that focus episode, and gesture/spring completion does not re-check the current confirmed target.

## Root cause

`preserveActiveViewport` conflates a temporary non-interference policy with permanent completion of focus reveal. It commits focus first, suppresses the only visibility check second, and carries no deferred obligation to prove that the accepted focus is visible when the preserving condition ends.

## Per-reason policy boundary

| Reason | Evidence | Required policy boundary |
| --- | --- | --- |
| `.gesture` | Source-confirmed branch; no retained capture with `preserveActiveViewportReason=gesture` was found. | Do not fight the user's live drag synchronously. If the accepted token is still confirmed when the gesture ends and its column is parked relative to the resulting viewport, run a deferred reveal/reconciliation. Do not depend on another AX event. |
| `.springInFlight` | Confirmed failure above: one preserved pass, no duplicate, confirmed column became `hidden:left` at settle. | Preserve only when the spring's **destination viewport** already contains the newly confirmed target. If the destination parks it, retarget the spring or guarantee a post-settle reveal. |
| `.alreadyConfirmedFocusedWindowChanged` | The scroll-lock capture shows a harmless duplicate after a failed first engine pass; the existing unit test intentionally preserves a manual scroll away from a still-focused window. | Token equality is not a sufficient completion marker. Suppress a duplicate only when the current focus episode has no outstanding visibility obligation. Preserve deliberate scroll-away behavior after a completed focus/reveal episode. |
| `.closeRecoveryPin` | Active-workspace captures found the selected close-recovery target already visible. The retained offscreen close-pin samples were on an inactive workspace (`isWorkspaceActive=false`), where revealing or activating it would violate recovery locality. | Do not apply a generic parked-target override. On an active workspace, reject or redirect an invalid parked close successor before/while confirming it; on an inactive workspace, preserve the workspace boundary. Close-recovery ownership remains upstream of generic reveal policy. |

## Repair direction and planning boundary

A plan must not replace the four-way reason selection with one visibility exception. It needs two distinct concepts:

1. **Is the current viewport operation allowed to be interrupted now?**
2. **Has visibility work for this accepted focus episode actually been completed?**

The source already has enough geometry to answer whether a spring destination contains the target, but the snap context is currently built only inside the non-preserved reveal branch. A repair should make destination visibility available before finalizing the preservation outcome, or carry a bounded pending visibility obligation into gesture/spring completion.

Deduplication may participate by refusing to discard a known unfinished obligation, but it cannot be the sole mechanism: the confirmed spring failure had no duplicate event.

Close recovery should remain a separate focus-selection problem. If recovery policy says the viewport must stay anchored, the correct outcome is normally to keep/redirect focus to a stable visible target, not to accept a parked successor and then force a generic reveal.

## Validation requirements

### `.springInFlight` — required regression

Construct a spring whose destination is away from the target column, then confirm focus on that target through the production activation path.

Acceptance requires:

1. the confirmation occurs while `current != target` by more than the device-pixel tolerance;
2. the target is parked relative to the spring destination;
3. the handler does not settle with `confirmedManagedFocusToken` pointing at a hidden column;
4. either the spring is retargeted immediately or a deterministic post-settle reveal runs; and
5. a control case where the spring destination already contains the target preserves the original trajectory.

The existing `focusConfirmationPreservesActiveViewportSpring` test covers only item 5 and must not remain the sole spring contract.

### `.gesture` — required before changing policy

1. Begin a committed gesture.
2. Confirm a different target that is parked relative to the eventual gesture result.
3. Verify the live gesture is not synchronously stolen.
4. End/cancel the gesture.
5. Verify a still-current confirmed target is reconciled exactly once without waiting for another AX event.
6. Verify a newer focus change cancels the stale obligation.

### `.alreadyConfirmedFocusedWindowChanged` — preserve both meanings

- Keep the existing manual-scroll-away regression: a completed, already-confirmed focus episode must not snap back on an AX duplicate.
- Add a distinct unfinished-episode case: if an earlier pass was deferred and the target remains current and parked, deduplication must not erase the pending reconciliation.
- Retain the ordinary duplicate no-op after a successful reveal.

### `.closeRecoveryPin` — do not validate by viewport motion alone

- On an active workspace, a parked stale successor should be suppressed or redirected to the stable recovery target before it becomes the lasting confirmed focus.
- On an inactive workspace, the event must not activate/reveal that workspace merely to satisfy generic focus visibility.
- A genuine same-app user switch outside close recovery must still confirm and reveal normally.

### Runtime evidence

A validating capture must inline, for one token:

```text
ax_focus_confirm_before_activate
  preserveActiveViewportReason=<reason>
  wasAlreadyConfirmedFocus=<bool>
  currentViewStart=<value>
  targetViewStart=<value>

ax_focus_confirm_reveal_candidate | ax_focus_confirm_reveal_skipped

<gesture end or scroll_animation_stop>
  selectedNode=<same token or replacement>
  confirmedFocus=<same token or replacement>
  hidden=<nil|left|right>
```

A no-scroll result is not sufficient. The capture must prove whether the accepted focus target is visible after the preserving condition ends.

## Relationships

- [`20260728-scroll-lock-suppresses-hotkey-focus-reveal.md`](20260728-scroll-lock-suppresses-hotkey-focus-reveal.md) owns the lower-level `didReveal=false` result from Capture A. This discovery begins one layer above it.
- [`20260627-trackpad-fling-snap-overshoot-to-neighbor-column.md`](20260627-trackpad-fling-snap-overshoot-to-neighbor-column.md) contains a correct spring-preservation example: focus was confirmed on the same neighbor column the spring was already approaching. Together the captures show why `.springInFlight` must be conditioned on destination visibility rather than always enabled or always disabled.
- [`../completed/20260706-stable-viewport-on-window-close-recovery.md`](../completed/20260706-stable-viewport-on-window-close-recovery.md) owns the intentional close-recovery pins and stable-target policy.
- [`20260713-same-app-close-successor-reveals-before-actionable-removal.md`](20260713-same-app-close-successor-reveals-before-actionable-removal.md) owns the opposite close-recovery failure: missing recovery evidence allowed a parked successor to reveal before actionable removal. That finding is why `.closeRecoveryPin` cannot simply yield to every parked target.
