# Scroll lock suppresses explicit hotkey focus reveals (pure-layout bridge dispatch defaults to `.automatic`)

Status: discovery — root cause confirmed in source; fix candidate identified.

## Symptom

With Viewport Scroll Lock enabled on a workspace, pressing a directional focus
hotkey (focus left/right) onto a clipped or parked column changes the selection
but **never scrolls the viewport to reveal the target**. The focused window
stays partially or fully off-screen.

This contradicts the documented contract (`docs/viewport-navigation-spec.md`,
"Viewport Scroll Lock" section):

> Viewport Scroll Lock is a per-workspace runtime toggle. When enabled, it
> suppresses **background automatic reveals only**. Explicit user navigation
> (workspace-bar window clicks and focus commands) … keep working.

Explicit focus commands are supposed to reveal while locked. They do not.

## Runtime evidence

Captured on a 2-monitor setup (built-in Retina 2056×1329 + DELL P2423D),
`focusFollowsMouse=false`, `revealStyle=auto`. Workspace 3 held two 65%-wide
columns (windows `34788:188` and `853:17717`, each 1316 px wide, viewport
≈2028 px), scroll lock **on**.

User pressed focus-right from col0 onto col1, which was clipped at the right
edge:

```text
reason=focus_direction_dispatch direction=right
  currentToken=WindowToken(pid: 34788, windowId: 188)
  targetToken=WindowToken(pid: 853, windowId: 17717) targetResolved=true
  currentViewStart=-6.0 targetViewStart=-6.0

reason=ax_focus_confirm_reveal_candidate token=WindowToken(pid: 853, windowId: 17717)
  columnIndex=1 revealStyle=auto locked=true
  visibility=clipped(Nehir.AxisHideEdge.maximum)
  viewStart=-6.0 closest=604.2:rightEdge center=960.2:center
  currentViewStart=-6.0 targetViewStart=-6.0

reason=ax_focus_confirm_reveal_result token=WindowToken(pid: 853, windowId: 17717)
  columnIndex=1 isFFM=false didReveal=false
  currentViewStart=-6.0 targetViewStart=-6.0
```

The target was `clipped`, snap candidates existed (`closest=604.2`,
`center=960.2`), `isFFM=false` — yet `didReveal=false` and the viewport stayed
pinned at `viewStart=-6.0` throughout. Selection moved (relayout rebased
`currentOffset` from `-6.0` to `-1328.1` for the new active column), but the
render viewport never scrolled; col1 remained mostly off-screen.

Across the whole capture (~26 s, six `ax_focus_confirm_reveal_result` events on
two workspaces, all with `locked=true` at candidate time): **every reveal
returned `didReveal=false`**. The only viewport motions were an explicit
workspace-bar navigation (`navigate.window source=workspaceBarWindow`) and a
reveal on a workspace observed with `locked=false`
(`currentViewStart=594.7 → targetViewStart=1011.0`, settling at `1011.0`) —
confirming the reveal machinery itself works and the suppression is
lock-specific.

## Root cause (confirmed in source)

There are **two reveal entry points** for a focus change, with different
trigger policies:

1. **Layout-command path** — `NiriLayoutHandler.focusNeighbor(direction:)`
   (`NiriLayoutHandler.swift:1458`, dispatched from
   `CommandHandler.performCommand` `:56`) →
   `NiriNavigation.focusTarget` → `ensureSelectionVisible(...,
   revealTrigger: .explicitNavigation)` (`NiriNavigation.swift:306`, and the
   sibling call sites at `:103, :331, :419, :558, :589, :654, :685`). This path
   correctly bypasses scroll lock: `RevealTrigger.explicitNavigation` has
   `respectsScrollLock == false` (`NiriLayoutEngine.swift:16-18`), so the guard
   in `scrollToReveal`
   (`NiriLayoutEngine+ViewportCommands.swift:102, :131`)

   ```swift
   guard !trigger.respectsScrollLock || !state.isScrollLocked else { return false }
   ```

   passes while locked.

   **However**, for a horizontal directional focus the actual traversal runs
   through `pureLayoutFocusTarget`
   (`NiriLayoutEngine+PureLayoutBridge.swift:28`), whose
   `ensureSelectionVisible` call (`:69-77`) passes **no `revealTrigger`**, so it
   defaults to `.automatic` (`NiriNavigation.swift:185`) — suppressed under
   lock. The `.explicitNavigation` call sites in `focusTarget` are the
   *fallback* branches that only run when the pure-layout reducer reports
   `.unsupported`.

   `focusNeighbor` is not the only explicit entry into this path.
   `NiriLayoutHandler.focusWindowOrWorkspace(direction:)`
   (`NiriLayoutHandler.swift:1726`, dispatched from
   `CommandHandler.performCommand` `:130` and `:132`) also calls
   `engine.focusTarget` (`:1736`) and is suppressed identically. Both entry
   points are explicit hotkey commands; `performCommand` has no background
   callers.

2. **AX focus-confirm path** — after the focus change is confirmed via
   Accessibility, `AXEventHandler` re-evaluates the reveal and calls
   `scrollToReveal` (`AXEventHandler.swift:4730-4738`) **without a `trigger:`
   argument**:

   ```swift
   let didReveal = engine.scrollToReveal(
       columnIndex: columnIndex,
       isFFM: isFFM,
       state: &state,
       context: context,
       motion: controller.motionPolicy.snapshot(),
       scale: engine.displayScale(in: wsId),
       allowFullyVisibleAutomaticRecenter: false
   )
   ```

   `scrollToReveal` declares `trigger: RevealTrigger = .automatic`
   (`NiriLayoutEngine+ViewportCommands.swift:79`), so this confirm-time reveal
   always runs as `.automatic` → suppressed whenever the workspace is locked,
   **regardless of whether the focus change was an explicit hotkey**. This is
   the call that produced the `didReveal=false` events above.

So an explicit hotkey focus is suppressed twice: once at dispatch time (the
pure-layout bridge's default `.automatic` trigger) and once at AX-confirm time
(the missing `trigger:` argument).

The two suppressions are **not independent**, and only the dispatch-time one
pins the viewport. `ViewportSnapContext.currentViewStart(in:)` returns
`state.targetViewPosPixels(...)` (`ViewportState+Geometry.swift:82-84`) — the
*target* viewport position, not the animated current one. So once the dispatch
reveal has set the target offset, the confirm-time reveal evaluates visibility
against the already-revealed position, reads `.fullyVisible`, and no-ops. A
confirm-time reveal left as `.automatic` therefore costs nothing once dispatch
is fixed; a dispatch-time reveal left as `.automatic` pins the viewport
regardless of what the confirm path does.

The trigger distinction exists only at call sites; nothing forces a focus
command entry point to declare itself explicit. `RevealTrigger` was introduced
with the intent that direct user navigation "may reveal while locked"
(doc comment at `NiriLayoutEngine.swift:13`), but these two paths never adopted
it.

## Why the confirm path lacks the context

At `AXEventHandler.swift:4730` the handler is reacting to an observed AX focus
event; it does not currently know whether the focus change originated from a
hotkey, a workspace-bar click, an app self-raise, or background churn. Passing
`.explicitNavigation` unconditionally there would let *background* focus
confirmations scroll a locked viewport — the exact thing the lock exists to
stop. Any fix must plumb (or infer) the trigger provenance:

- The dispatch path (`NiriLayoutHandler.focusNeighbor(direction:)` `:1458`,
  `focusWindowOrWorkspace(direction:)` `:1726`, `focusPrevious()` `:1571`, and
  workspace-bar window activation via `NavigationSource.workspaceBarWindow` →
  `WindowActionHandler.navigateToWindowInternal` `:469`) knows the trigger and
  already runs `scrollToReveal` synchronously with the right context. Note
  `navigateToWindowInternal` already passes
  `revealTrigger: .explicitNavigation` (`:501`) and is not affected by this
  bug.
- A short-lived "explicit navigation pending" latch keyed by the target token
  (analogous to existing latches like `recentParkedFocusFollowByToken`) could
  carry provenance to the confirm callback.

## Fix candidates

1. **Fix the dispatch-time reveal (primary):** pass
   `revealTrigger: .explicitNavigation` through
   `pureLayoutFocusTarget` → `ensureSelectionVisible`
   (`NiriLayoutEngine+PureLayoutBridge.swift:69`). This makes the hotkey's own
   dispatch reveal the target while locked, matching the spec. This alone may
   be sufficient: the AX-confirm reveal then finds the target already
   fully visible / already at target offset and correctly no-ops.
2. **Confirm-path provenance (secondary, if needed):** carry explicitness into
   the AX focus-confirm reveal via a token-keyed latch set by the explicit
   dispatch paths, and pass `trigger: .explicitNavigation` at
   `AXEventHandler.swift:4730` only when the latch matches. Without evidence
   that the confirm path must reveal cases the dispatch path missed, this may
   be unnecessary scope.

Decision needed before planning: whether fix 1 alone satisfies the spec'd
behavior — likely, per the `currentViewStart` reasoning above, but it should be
validated in the user's live repro.

There are no separate vertical/tabbed traversal variants inside the pure-layout
bridge to audit: `pureLayoutFocusTarget`
(`NiriLayoutEngine+PureLayoutBridge.swift:28`) is the single traversal entry
point and maps every direction through `PureDirection(direction:orientation:)`
(`:382`), so the one `ensureSelectionVisible` call at `:69` covers horizontal,
vertical, and tabbed movement alike. All eight `ensureSelectionVisible` call
sites in `NiriNavigation.swift` (`:103, :306, :331, :419, :558, :589, :654,
:685`) already pass `.explicitNavigation`.

## Verification notes

- Source citations verified against the main Nehir source tree on 2026-07-28.
- Existing regression coverage: `Tests/NehirTests/ViewportSnapContextTests.swift`
  exercises `isScrollLocked` with `scrollToReveal` directly, but no test covers
  the trigger plumbing from a focus command through the pure-layout bridge, and
  none covers the AX focus-confirm call site.
- Per repo testing rules, tests are written only after the user confirms the
  fix in their real repro.
