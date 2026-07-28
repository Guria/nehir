# Scroll lock leaves a focused window entirely off-screen

**Status:** completed; shipped on `main` as `ff6b7043..a08f35a3` (2026-07-28),
four commits, no merge commit.

**Final shipped state:** viewport scroll lock answers to **target visibility**,
not to reveal provenance. On a locked workspace exactly one case moves the
viewport — a `.parked` target, i.e. one entirely outside the viewport — and it
moves for every trigger. `.clipped` and `.fullyVisible` targets are left alone
for every trigger. Unlocked behaviour is unchanged.

This is **broader than the fix candidates recorded below**, and the difference
matters when reading the rest of this document: validation with the user
overturned two of its premises. See "How validation changed the conclusion".

## Symptom

With Viewport Scroll Lock enabled on a workspace, focusing a window whose column
sits **entirely outside the viewport** changes the selection but never scrolls
the viewport to reveal it. The window takes focus while staying invisible, and
keyboard input disappears into it.

The original framing of this document also treated a **clipped** target as part
of the defect, quoting `docs/viewport-navigation-spec.md`:

> Viewport Scroll Lock is a per-workspace runtime toggle. When enabled, it
> suppresses **background automatic reveals only**. Explicit user navigation
> (workspace-bar window clicks and focus commands) … keep working.

That reading did not survive validation. A partially visible target is one the
user can already see, and dragging it to a snap is the churn the lock exists to
stop — so the clipped half of the original symptom is now expected behaviour.

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

## Root cause (confirmed in source, pre-fix code)

The plumbing described in this section is accurate for the code as it stood
before `ff6b7043`. The defaults it relies on no longer exist — see
"What shipped".


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
- Pre-fix regression coverage: `Tests/NehirTests/ViewportSnapContextTests.swift`
  exercised `isScrollLocked` with `scrollToReveal` directly, but no test covered
  the trigger plumbing from a focus command through the pure-layout bridge, and
  none covered the AX focus-confirm call site.
- Per repo testing rules, tests were written only after the user confirmed the
  fix in their real repro.

## How validation changed the conclusion

Two premises of the analysis above did not survive the user's review.

**1. A clipped target must not be revealed while locked — at any visible
fraction.** The document treated the first capture as the defect, but its target
was `clipped`, not parked: two 1316 px columns on a ≈2028 px viewport at
`viewStart=-6.0` left roughly 700 px of column 1 visible, about 53%. The user's
position is that scroll lock exists precisely to stop the viewport being dragged
to a snap for a column that is already partly on screen, and that this holds even
at 5% visible. So that capture documents expected behaviour, and the fix
candidates below would have made it worse rather than better.

**2. Provenance is the wrong axis.** A second capture, on a workspace with five
1011 px columns at `viewStart=1011.0` and scroll lock on, switched between
windows of one browser through that app's own Window menu:

```text
reason=ax_focus_confirm_reveal_candidate columnIndex=4 revealStyle=auto
  locked=true visibility=parked(Nehir.AxisHideEdge.maximum)
  viewStart=1011.0 closest=3045.0:rightEdge closestFills=true
  center=3553.5:center snapCount=3

reason=ax_focus_confirm_reveal_result columnIndex=4 isFFM=false didReveal=false
```

The target column sat at `x=4068.0`, entirely outside the viewport, with usable
snap candidates and `isFFM=false` — and nothing moved. That focus arrives through
AX focus confirmation, so it carries `.automatic` no matter how deliberate the
user's action was. Any rule keyed on provenance strands it. The same capture also
showed two `fullyVisible` targets correctly returning `didReveal=false`.

Together these inverted the policy: what decides a locked viewport is whether the
user can see the target at all, not who asked.

## What shipped

`ff6b7043` — the reveal policy. The two per-branch
`guard !trigger.respectsScrollLock || !state.isScrollLocked` checks in
`scrollToReveal` are replaced by a single gate evaluated once the target's
visibility is known:

```swift
if state.isScrollLocked {
    guard case .parked = visibility else { return false }
}
```

`RevealTrigger.respectsScrollLock` is deleted with them; it no longer decided
anything. `RevealTrigger` survives and still governs one narrower question —
whether an already fully visible **non-filling** column may be re-centred
(`.explicitNavigation`, or `.automatic` with
`allowFullyVisibleAutomaticRecenter`, and only when `revealStyle == .auto`).
Re-centring a fully visible column that *fills* the viewport is viewport
maintenance and runs for either trigger.

Fix candidate 1 below shipped as part of this commit —
`pureLayoutFocusTarget` now passes `revealTrigger: .explicitNavigation` — but it
is no longer what repairs the reported behaviour. Under the visibility rule the
bridge's trigger only affects fully-visible re-centring.

Fix candidate 2 (a token-keyed provenance latch for the AX confirm path) was
**not** implemented and is no longer needed: the confirm path reveals a parked
target on its own now that provenance is out of the decision.

`1a1aec68` — removes the `= .automatic` default from `ensureSelectionVisible`,
`scrollToReveal` and `ensureColumnVisible`. The default was the mechanism by
which this bug entered: the bridge simply omitted the argument. Fifteen
background call sites now pass `.automatic` explicitly; omitting it is a compile
error. Regression coverage lands in `Tests/NehirTests/ScrollLockRevealPolicyTests.swift`
and `Tests/NehirTests/ScrollLockFocusCommandRevealTests.swift`.

Two pre-existing tests encoded the replaced contract and were rewritten rather
than adapted: `ViewportSnapContextTests.scrollToRevealSkipsWhenLocked` (asserted
a parked target stays hidden while locked) was deleted in favour of the new
per-behavior coverage, and the IPC router's
`windowFocusBypassesViewportScrollLockForExplicitNavigation` — whose target
window landed in the clipped column at that fixture's geometry — now asserts the
viewport holds still, with a sibling test covering the parked case.

`4bafe3ca` and `a08f35a3` are follow-ups: formatting and provenance
registration, then moving the IPC scroll-lock tests into their per-behavior file.

Changeset: `patch`. No ticket number; none existed for this work.

## Follow-ups

- [`20260728-preserve-active-viewport-can-strand-confirmed-focus-offscreen.md`](../discovery/20260728-preserve-active-viewport-can-strand-confirmed-focus-offscreen.md)
  — `AXEventHandler` skips the reveal call entirely when `preserveActiveViewport`
  is set, which sits above the engine and therefore above the policy shipped
  here. In the second capture the parked target's first confirm pass ran with
  `preserve=none` and was killed by the old lock guard, while a later duplicate
  pass was skipped with `preserveActiveViewportReason=already_confirmed_focused_window_changed`;
  an ordering where only preserve-branch passes occur would strand the window
  again.
- [`20260728-action-catalog-binding-literals-are-not-shipped-defaults.md`](../discovery/20260728-action-catalog-binding-literals-are-not-shipped-defaults.md)
  — surfaced while tracing which hotkey reaches this path.

## Known documentation drift

`docs/viewport-navigation-spec.md` on `main` still describes the replaced
contract and now contradicts shipped behaviour in two places: the "Reveal on
Focus" table row *"Explicit user navigation with a clipped or parked target →
Yes, using Reveal Style"*, and the "Viewport Scroll Lock" paragraph stating the
lock *"suppresses background automatic reveals only"* while explicit user
navigation *"keeps working"*. Both now overstate what a locked workspace does.
The same table's *"Target already fully visible → Never"* row was already stale
before this change, since `c6eaafb9` allows explicit navigation to re-centre a
fully visible column. Updating that spec is outstanding.
