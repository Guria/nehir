# Browser reactivation overrides a newly confirmed Ghostty window and steals the resize target

**Status:** source-backed root cause. Verified against `main` at `fe0596b6` on
2026-07-26. The runtime sequence proves which focus event changed the target and
which window each resize command acted on. The exact AppKit/Ghostty reason macOS
emitted the browser activation remains unproven; that uncertainty does not affect
the confirmed Nehir-side arbitration failure.

## Executive verdict

A normal Ghostty window was admitted, selected, and confirmed as managed focus.
One second later macOS delivered `NSWorkspace.didActivateApplicationNotification`
for the previously focused Helium browser. Nehir accepted that app-level event as
an unrelated activation on the already-active workspace, confirmed the browser,
and changed the Niri `selectedNodeId` back to the browser. The next two
column-width commands therefore resized Helium, because `cycleSize` deliberately
targets `selectedNodeId`.

The fundamental defect is not in width calculation. It is that the activation
layer cannot distinguish a deliberate user app switch from an automatic
cross-app focus return, yet it lets either one replace a freshly confirmed
managed window as soon as that window's focus request has completed. Existing
overlay/close-recovery guards do not cover this shape: their evidence is keyed to
the observed successor pid or requires an inactive workspace, while this event
was for a different pid on the same active workspace after Ghostty confirmation
had already cleared non-managed focus.

## Topology and identities

Single built-in display:

```text
displayId=1
frame=(0,0 2056x1329)
visibleFrame=(0,0 2056x1290)
focusFollowsMouse=false
workspace=3FCEFFBA-2C76-4DA3-ACB8-1CAD2FC3A64E
```

Relevant windows:

```text
Ghostty quick-terminal overlay
  token=WindowToken(pid: 912, windowId: 124)
  bundleId=com.mitchellh.ghostty
  AXSubrole=AXFloatingWindow
  WindowServer level=101
  decision=unmanaged source=builtInRule(ghosttyQuickTerminalOverlay)

New regular Ghostty window
  token=WindowToken(pid: 912, windowId: 205)
  bundleId=com.mitchellh.ghostty
  AXSubrole=AXStandardWindow
  mode=tiling

Previously focused browser
  token=WindowToken(pid: 79206, windowId: 173)
  bundleId=net.imput.helium
  AXSubrole=AXStandardWindow
  mode=tiling
```

The final model inventory independently identifies `912:205` as Ghostty and
`79206:173` as Helium.

## Runtime sequence

### 1. The overlay preserves Helium as managed focus

Immediately before the regular Ghostty window is created, unmanaged overlay
focus is active while Helium remains the preserved managed token:

```text
11:00:15 non_managed_focus_changed active=true preserve=true
  focused=WindowToken(pid: 79206, windowId: 173)

11:00:16 non_managed_focus_changed active=true preserve=true
  focused=WindowToken(pid: 79206, windowId: 173)
```

This is consistent with the recognized Ghostty quick-terminal window `912:124`
being unmanaged while the browser is the managed focus anchor.

### 2. The new Ghostty window is admitted and confirmed

At `11:00:17`, regular Ghostty window `912:205` is admitted as a tiled window in
the active workspace:

```text
window_admitted token=WindowToken(pid: 912, windowId: 205)
  mode=tiling context=focused_admission

managed_focus_requested token=WindowToken(pid: 912, windowId: 205)
  previouslyFocused=WindowToken(pid: 79206, windowId: 173)

managed_focus_confirmed token=WindowToken(pid: 912, windowId: 205)
```

The Niri state agrees. The new window is column 1 and is the selected node:

```text
columns=2 activeColumnIndex=1
selected=w205
preferredFocus=WindowToken(pid: 912, windowId: 205)
confirmedFocus=WindowToken(pid: 912, windowId: 205)
resizeCommandSeq=0
```

The insertion record also says the window landed relative to the browser's
focused column:

```text
token=WindowToken(pid: 912, windowId: 205)
beforeColumns=1
focusedTokenBefore=WindowToken(pid: 79206, windowId: 173)
landedColumn=1
```

At this point Nehir's managed state correctly represents the user's intended
Ghostty target.

### 3. A Helium app activation is allowed to replace Ghostty

At `11:00:18`, an external `workspaceDidActivateApplication` event resolves to
Helium `79206:173`. The activation gate records all the facts needed to show why
current guards miss it:

```text
token=WindowToken(pid: 79206, windowId: 173)
isWorkspaceActive=true
source=workspaceDidActivateApplication
origin=external
requestDisposition=unrelatedNoRequest
activeRecoveryWorkspace=nil
recentSameAppClose=false
recentNonManagedFocus=false
overlayCapablePid=false
nonManagedFocusActive=false
overlayVisible=false
sameAppCloseOrOverlayEvidence=false
currentTarget=WindowToken(pid: 912, windowId: 205)
currentTargetManaged=true
currentTargetSamePid=false
decision=allow reason=no_close_or_overlay_evidence
```

The decisive contradiction is explicit: the current managed target is the newly
confirmed Ghostty window, but the unrelated browser activation is allowed.

Nehir then confirms and selects Helium:

```text
managed_focus_confirmed token=WindowToken(pid: 79206, windowId: 173)

ax_focus_confirm_after_activate token=WindowToken(pid: 79206, windowId: 173)
columns=2 activeColumnIndex=1
selected=w173
preferredFocus=WindowToken(pid: 79206, windowId: 173)
confirmedFocus=WindowToken(pid: 79206, windowId: 173)

ax_focus_confirm_request_relayout token=WindowToken(pid: 79206, windowId: 173)
columns=2 activeColumnIndex=0
selected=w173
```

No resize has happened yet. The wrong command target has already been created by
focus confirmation.

### 4. The resize commands faithfully act on the browser selection

The first two resize commands arrive much later, with Helium still selected:

```text
11:00:31 cmd=1 compute kind=toggleColumnWidth(forward)
  columnIndex=0 window=173
  previous=1011.0 newSpec=proportion(0.6500)

11:00:31 cmd=1 apply
  columnIndex=0 window=173 targetPixels=1316.1

11:00:32 cmd=2 compute kind=toggleColumnWidth(forward)
  columnIndex=0 window=173
  previous=1316.1 newSpec=proportion(0.9500)

11:00:32 cmd=2 apply
  columnIndex=0 window=173 targetPixels=1926.3
```

The concurrent viewport state names the same target:

```text
selected=w173
preferredFocus=WindowToken(pid: 79206, windowId: 173)
confirmedFocus=WindowToken(pid: 79206, windowId: 173)

c0 ... w173:selected ... spec=prop:0.9500
c1 ... w205          ... spec=prop:0.5000
```

Thus the browser's column changes from 50% to 65% to 95%, while Ghostty remains
at 50%.

### 5. Explicitly selecting Ghostty makes subsequent resizes correct

At `11:00:34`, a focus-right command moves selection from Helium to Ghostty:

```text
focus_direction_dispatch direction=right
currentToken=WindowToken(pid: 79206, windowId: 173)
targetToken=WindowToken(pid: 912, windowId: 205)
resultingSelectedToken=WindowToken(pid: 912, windowId: 205)
```

After Ghostty is confirmed, commands 3 and 4 correctly act on `window=205`:

```text
11:00:35 cmd=3 apply kind=toggleColumnWidth(forward)
  columnIndex=1 window=205 targetPixels=1316.1

11:00:37 cmd=4 apply kind=toggleColumnWidth(forward)
  columnIndex=1 window=205 targetPixels=1926.3
```

This control rules out a sizing-engine identity error. The resize implementation
uses whichever node activation left selected.

## Controlled reproduction isolates the quick-terminal close handoff

A controlled repetition separated the two operations that can otherwise be
mistaken for one lifecycle event: Command+N created a regular Ghostty window while
the quick terminal remained open, and the quick terminal was then closed with its
own toggle shortcut.

### Creating a regular window replaces the preserved browser anchor

At `12:30:31`, the recognized quick-terminal overlay `912:124` was the only Ghostty
AX window. Non-managed focus preserved Helium `79206:173`:

```text
ax_windows_query pid=912 count=1 windowIds=[124]
non_managed_focus_changed active=true preserve=true
  focused=WindowToken(pid: 79206, windowId: 173)
```

At `12:30:34`, Command+N produced regular Ghostty window `912:562` while the
overlay was still present:

```text
ax_windows_query pid=912 count=2 windowIds=[124, 562]
window_admitted token=WindowToken(pid: 912, windowId: 562) mode=tiling
managed_focus_requested token=WindowToken(pid: 912, windowId: 562)
managed_focus_confirmed token=WindowToken(pid: 912, windowId: 562)
```

The corresponding managed request was explicit and targeted Ghostty:

```text
pending_focus_started request=91
  token=WindowToken(pid: 912, windowId: 562)
  reason=layoutRefreshRememberedFocus
```

The viewport settled with Ghostty selected and confirmed:

```text
columns=2 activeColumnIndex=1
selected=w562
preferredFocus=WindowToken(pid: 912, windowId: 562)
confirmedFocus=WindowToken(pid: 912, windowId: 562)
currentViewStart=-6.0 targetViewStart=-6.0
```

This proves that the preserved Helium token was no longer the live managed-focus
anchor before the overlay closed. Ghostty confirmation had replaced it and cleared
non-managed focus.

### Closing the overlay is immediately followed by an unattributed Helium activation

At `12:30:37`, closing the quick terminal destroyed `912:124`; the remaining
Ghostty AX inventory contained only regular window `912:562`:

```text
ax=AXUIElementDestroyed pid=912 window=124
ax_windows_query pid=912 count=1 windowIds=[562]
```

In the same second, Nehir received a Helium app activation. The gate saw the newly
confirmed Ghostty window as the current managed target, but had neither an active
Nehir focus request nor recovery evidence for the cross-app successor:

```text
token=WindowToken(pid: 79206, windowId: 173)
source=workspaceDidActivateApplication
origin=external
requestDisposition=unrelatedNoRequest
activeRecoveryWorkspace=nil
recentSameAppClose=false
recentNonManagedFocus=false
overlayCapablePid=false
nonManagedFocusActive=false
currentTarget=WindowToken(pid: 912, windowId: 562)
currentTargetManaged=true
currentTargetSamePid=false
decision=allow reason=no_close_or_overlay_evidence
```

There is no `managed_focus_requested` or `pending_focus_started` record for Helium
in this reproduction after request 91. Native reality nevertheless confirms that
the switch was real rather than merely a stale notification:

```text
focus_confirmed token=WindowToken(pid: 79206, windowId: 173)
app_frontmost=true
app_focused_window=173
```

Nehir then selected Helium. Both half-width columns were already fully visible, so
this selection theft did not require visible viewport movement at close time. The
next command at `12:30:41` exposed the state change by resizing Helium:

```text
cmd=8 compute kind=toggleColumnWidth(forward)
  columnIndex=0 window=173
  previous=1011.0 newSpec=proportion(0.6500)
```

This is an important policy refinement: viewport stability alone is insufficient.
Closing a non-flow surface must also preserve the current managed layout selection
and command target when that target remains valid. When several candidates require
zero viewport displacement, preserving the existing selected token must win the
tie.

### The no-new-window control exercises the existing same-pid protection

In the control repetition, Helium `79206:173` remained selected on the active
workspace while regular Ghostty window `912:562` existed on an inactive workspace.
Closing quick terminal `912:124` caused native focus churn toward that inactive
same-pid Ghostty window. Nehir deferred it for 120 milliseconds:

```text
token=WindowToken(pid: 912, windowId: 562)
isWorkspaceActive=false
source=focusedWindowChanged
origin=external
currentTarget=WindowToken(pid: 912, windowId: 124)
confirmedFocus=WindowToken(pid: 79206, windowId: 173)
reason=overlay_close_churn_deferred
```

After the overlay destruction became observable, the retry had
`recentSameAppClose=true` with age 125 milliseconds and was suppressed:

```text
reason=overlay_close_churn_suppressed
recentSameAppClose=true
recoveryArmed=false
clearedStaleNonManagedFocus=true
reason=close_evidence_present
```

Helium remained selected and the inactive Ghostty workspace was not activated.
This control shows that current same-pid close suppression works for the event
shape it can correlate. The failing reproduction differs precisely at the
cross-app successor: Ghostty owns the overlay, while Helium emits the accepted
activation.

### Experiment verdict

The experiment confirms only the first half of the historical-focus theory:
Helium is preserved while the quick terminal owns non-managed focus. It disproves
the proposed Nehir restore mechanism. By overlay close time the live confirmed
token is Ghostty `912:562`; there is no Nehir focus request to Helium and no active
`WindowCloseFocusRecoveryContext` redirect. The Helium activation enters from the
external NSWorkspace observer and is then accepted as unattributed.

The experiment does not identify which native component initiated that real
cross-app switch. It does prove that the switch is tightly coupled to the separate
quick-terminal close operation, reproduces the original target theft, and bypasses
protection because the observed successor pid differs from the overlay owner pid.

## Source-backed causal chain

### 1. The app-activation observer carries pid, not activation cause

`ServiceLifecycleManager.setupAppActivationObserver` subscribes to
`NSWorkspace.didActivateApplicationNotification`, extracts only the process id,
and calls:

```swift
controller?.axEventHandler.handleAppActivation(
    pid: pid,
    source: .workspaceDidActivateApplication
)
```

(`Sources/Nehir/Core/Controller/ServiceLifecycleManager.swift:461-477`.)

The callback does not say whether activation came from Cmd-Tab, Dock, a user
click, app startup, an overlay yielding focus, or AppKit restoring the prior app.
Those causes are indistinguishable by the time `AXEventHandler` receives them.

### 2. The handler deliberately treats every external app activation as user intent

`handleAppActivation` documents app-level activation as a “genuine app-level
switch” and “user-intent signal,” records it in `recentAppActivationByPid`, and
starts a `nativeAppSwitch` lease when it matches neither an active managed request
nor a recently confirmed request for the same token
(`Sources/Nehir/Core/Controller/AXEventHandler.swift:3737-3787`). This policy was
introduced to preserve real Dock/Cmd-Tab/launcher activation of
existing-but-untracked windows; commit `151f4e3a` explicitly describes
`workspaceDidActivateApplication` as deliberate user intent.

That assumption is too broad for the captured handoff: the user created and
intended to resize Ghostty, but a later Helium activation notification was granted
the same authority.

The `nativeAppSwitch` lease does not serialize app switches or protect the current
target. `FocusPolicyEngine.evaluate(.managedAppActivation)` allows managed app
activation under every lease except a non-authoritative event during a native-menu
lease (`Sources/Nehir/Core/Reconcile/FocusPolicyEngine.swift:84-96`). Therefore
the Ghostty app-switch lease visible in the runtime state cannot reject the later
Helium activation.

### 3. Ghostty confirmation removes the state that could have anchored the handoff

`handleManagedAppActivation` calls `confirmManagedFocus` for the Ghostty token
(`Sources/Nehir/Core/Controller/AXEventHandler.swift:4510-4518`). The focus reducer
then sets:

```swift
focusSession.focusedToken = token
focusSession.pendingManagedFocus = .empty
focusSession.isNonManagedFocusActive = false
```

(`Sources/Nehir/Core/Reconcile/StateReducer.swift:317-329`.)

This is correct for a completed managed focus transition, but it means the browser
activation one second later sees both:

- no active managed request; and
- `isNonManagedFocusActive=false`.

`activationRequestDisposition` returns `.unrelatedNoRequest` whenever
`activeRequest` is nil (`Sources/Nehir/Core/Controller/AXEventHandler.swift:7423-7437`).
There is a 0.6-second `nativeAppSwitchLeaseRequestConfirmationGrace`
(`AXEventHandler.swift:898,3767-3773`), but it only recognizes an activation for
the same recently confirmed token and suppresses creation of another
`nativeAppSwitch` lease. It neither classifies nor rejects a contradictory
cross-pid activation, and the Helium event arrived about one second after the
Ghostty confirmation. There is therefore no post-confirmation handoff guard for
this event shape.

### 4. Overlay evidence is same-pid, but the successor is cross-app

Quick-terminal observation records recent non-managed focus under the overlay
window's pid. `recordPrepareCreateRejection` calls
`recordRecentNonManagedFocus(pid: token.pid)` when a recognized unmanaged overlay
is rejected (`Sources/Nehir/Core/Controller/AXEventHandler.swift:5567-5573`), and
the evidence map is keyed by pid (`AXEventHandler.swift:6493-6507`).

Recovery lookup is also same-pid:

```swift
let recentNonManaged = hasRecentNonManagedFocus(for: entry.pid)
let overlayVisible = hasVisibleSamePidOverlayWindow(for: entry)
```

(`Sources/Nehir/Core/Controller/AXEventHandler.swift:2768-2773`.)

For the observed browser entry, `entry.pid` is Helium `79206`, not overlay owner
Ghostty `912`. The gate therefore reports `recentNonManagedFocus=false`,
`overlayCapablePid=false`, and `overlayVisible=false` even though the sequence
started under a recognized Ghostty overlay. The current evidence model cannot
associate a cross-app return-to-origin activation with the overlay handoff that
preceded it.

### 5. Every relevant suppression gate structurally misses this event

The browser activation is a different-pid window on the same active workspace:

- `shouldSuppressManagedActivationWhileNonManagedFocusAnchored` requires
  `isNonManagedFocusActive` or a visible same-pid overlay for the *observed*
  entry (`Sources/Nehir/Core/Controller/AXEventHandler.swift:3042-3066`). Both
  are false after Ghostty confirmation and for Helium.
- `shouldDeferInactiveNativeActivationBeforeCloseRecovery` requires
  `!isWorkspaceActive` (`AXEventHandler.swift:3191-3247`). Helium is on the
  active workspace.
- `shouldSuppressObservedActivationDuringWindowCloseRecovery` requires an active
  close-recovery context (`AXEventHandler.swift:2594-2629`). There is none.
- The overlay-specific guards are deliberately same-app and therefore do not
  treat a Helium activation as Ghostty overlay churn.
- For `.unrelatedNoRequest`,
  `shouldHandleObservedManagedActivationWithoutPendingRequest` returns `true`
  immediately when the target workspace is active
  (`AXEventHandler.swift:7440-7453`).

The diagnostic `currentTarget=912:205 currentTargetManaged=true` does not become a
decision input. `recordCloseRecoveryActivationGate` records that target, but no
general same-workspace cross-app guard asks whether a newly confirmed managed
target is fresher than the incoming app notification.

### 6. Accepting the event rewrites the exact state resize consumes

`handleManagedAppActivation` first confirms Helium as managed focus
(`AXEventHandler.swift:4510-4547`), then calls `activateNode` and
`rebaseViewportAnchor` on Helium's Niri node
(`AXEventHandler.swift:4664-4681`). This changes `selectedNodeId` to window 173.

`NiriLayoutHandler.cycleSize` later reads `state.selectedNodeId`, resolves its
`NiriWindow` and containing column, and passes that column to
`toggleColumnWidth` (`Sources/Nehir/Core/Controller/NiriLayoutHandler.swift:1863-1881`).
It does not re-resolve live user intent or compare against the window that was
newly created. Once the activation path selected Helium, resizing Helium was the
specified behavior of the sizing path.

## Five-why analysis

### Why 1: Why did the browser resize?

Because both resize commands targeted Niri column 0 containing Helium window
`79206:173`; the resize trace explicitly records `window=173`.

### Why 2: Why was Helium the resize target?

Because `selectedNodeId` had been changed from Ghostty `912:205` to Helium
`79206:173` thirteen seconds before the first resize command.

### Why 3: Why did selection move back to Helium after Ghostty was confirmed?

An external `workspaceDidActivateApplication` for Helium was accepted as
`.unrelatedNoRequest` and sent through `handleManagedAppActivation`, which
confirms focus and activates the observed Niri node.

### Why 4: Why did no guard reject that contradictory activation?

Ghostty confirmation had already cleared non-managed focus and completed the
managed request. The event was cross-app and same-workspace, so same-pid overlay
recovery and inactive-workspace guards did not apply. Overlay evidence was stored
under Ghostty's pid but looked up under Helium's pid.

### Why 5: Why can this class of contradictory event become command authority?

The activation architecture equates an external app-level notification with a
user-intent app switch even though the observer carries no causality. It protects
pending requests, same-app overlay churn, and inactive-workspace re-homing, but
has no arbitration rule for an automatic cross-app activation that arrives just
after a different app's new managed window was confirmed on the same workspace.

## Root cause

**Nehir promotes cause-less `NSWorkspace.didActivateApplicationNotification`
events to managed-focus and Niri-selection authority without a
post-confirmation or cross-app overlay-handoff check.**

The captured browser event arrived after Ghostty's focus request had completed,
so it was classified as unrelated rather than conflicting. The same-workspace
fast path then accepted it, despite the gate observing a different current
managed target. Since overlay evidence is keyed to the observed entry's pid, the
Ghostty overlay context could not qualify the Helium successor. The accepted
event replaced Ghostty selection, and resize correctly followed that replaced
selection.

## Confidence boundaries

### Confirmed

1. `912:205` is a regular managed Ghostty window; `79206:173` is a managed Helium
   browser window.
2. Ghostty was admitted, requested, confirmed, and selected before any resize.
3. A later external `workspaceDidActivateApplication` for Helium was classified
   `.unrelatedNoRequest` and explicitly allowed while
   `currentTarget=912:205`.
4. That activation confirmed Helium and changed Niri selection to window 173.
5. Resize commands 1 and 2 targeted window 173 and changed its column from 50%
   to 65% to 95%; Ghostty remained at 50%.
6. After explicit navigation selected Ghostty, resize commands 3 and 4 targeted
   window 205 correctly.
7. Current source contains the exact permissive same-workspace path and the exact
   selected-node resize path required for this sequence.
8. A controlled repetition in which Command+N and quick-terminal close were
   separate operations reproduced the sequence with regular Ghostty window
   `912:562`.
9. Ghostty `912:562` replaced the preserved Helium token before overlay close;
   there was no later Nehir focus request or active close-recovery redirect to
   Helium.
10. The Helium activation coincided with destruction of quick terminal `912:124`,
    and native reality then reported Helium frontmost with focused window 173.
11. A control without new-window creation exercised same-pid inactive-workspace
    churn toward Ghostty `912:562`; Nehir deferred it until close evidence arrived
    and then suppressed it, leaving Helium selected.

### Not proven

1. Which native mechanism initiated Helium's real activation when quick terminal
   closed: Ghostty/AppKit yielding focus, macOS restoring the prior app, or another
   native app-level behavior outside Nehir's managed-focus request path.
2. Whether every way of creating a Ghostty window from the quick terminal
   reproduces the activation ordering.

The fix boundary should not depend on selecting one of these native explanations.
The source-level defect is that all of them are granted the same authority as an
explicit user app switch.

## Relationship to existing discoveries

- [`20260713-resize-command-target-offscreen-selection.md`](20260713-resize-command-target-offscreen-selection.md)
  establishes the shared downstream rule: sizing trusts `selectedNodeId`. That
  discovery's selection divergence came from focus validation restoring an
  offscreen token. Here selection is changed by an accepted cross-app activation,
  so this is a new arming path, not a duplicate root.
- [`20260718-sibling-click-focus-never-observed-no-reveal-resize-stale-target.md`](20260718-sibling-click-focus-never-observed-no-reveal-resize-stale-target.md)
  also ends with resize following stale selection, but there the intended focus
  notification never arrived. Here the intended Ghostty confirmation did arrive;
  a later browser activation overwrote it.
- [`20260709-window-close-successor-app-activation-reveals-far-parked-column.md`](20260709-window-close-successor-app-activation-reveals-far-parked-column.md)
  is the closest policy sibling: a cross-app successor activation is treated as
  a real app switch. Its trigger is a managed-window close and its visible result
  is a far-column reveal. This capture has no managed-window removal before the
  target theft; it is a new-window/overlay handoff on the same active workspace.
  A fix keyed only to recent managed-window destruction would not cover it.
- [`../completed/20260709-quick-terminal-long-open-close-reveals-parked-ghostty-viewport.md`](../completed/20260709-quick-terminal-long-open-close-reveals-parked-ghostty-viewport.md)
  fixed same-app Ghostty focus redirects around quick-terminal open/close. Its
  guards are intentionally same-pid and therefore do not catch the Helium
  cross-app return in this capture.
- [`../completed/20260710-ghostty-quick-terminal-arms-stale-nonmanaged-focus.md`](../completed/20260710-ghostty-quick-terminal-arms-stale-nonmanaged-focus.md)
  fixed non-managed focus remaining armed after a suppressed same-app redirect.
  Here non-managed focus clears correctly when Ghostty is confirmed; the failure
  is the later cross-app overwrite.

## Compatibility constraints for a future plan

1. Preserve genuine user-driven Dock, Cmd-Tab, launcher, and click app switches,
   including activation of existing-but-untracked windows. This is the behavior
   protected by commit `151f4e3a`.
2. Preserve managed confirmation clearing non-managed focus when a real managed
   window takes focus.
3. Preserve same-app quick-terminal close suppression and viewport stability from
   the landed CR-1 fixes.
4. Do not change resize semantics as a substitute for fixing focus arbitration.
   Width commands acted consistently with selection; validating the target at
   command time may be useful defense-in-depth, but it would leave every other
   selected-node command exposed to the same wrong activation.
5. Do not use a broad time-only rule that ignores all cross-app activations after
   a create; a user may legitimately create a window and immediately switch apps.
   The distinguishing evidence must include causality or corroboration, not only
   recency.

## Investigation and fix boundary

The narrow source boundary is the `.unrelatedNoRequest` branch for
`workspaceDidActivateApplication` in `AXEventHandler.handleAppActivation`, before
`handleManagedAppActivation` is allowed to replace a different, freshly confirmed
managed target on the same active workspace.

A plan should evaluate mechanisms that retain genuine app-switch behavior while
requiring additional evidence for this contradictory handoff, for example:

- a short-lived post-confirmation handoff record containing the confirmed token,
  pid, request id, admission/create context, and prior non-managed overlay owner;
- corroboration from the current frontmost pid and focused AX window at decision
  time, with explicit handling for delayed/out-of-order app notifications;
- carrying the overlay-to-managed-window transition as a causal transaction
  rather than looking up recovery evidence only by the incoming successor pid;
- sequence/revision arbitration so an app activation observed before a newer
  managed confirmation cannot commit after it.

The controlled reproduction now proves that the event follows a separate overlay
close, has no Nehir managed-focus request behind it, and agrees with live native
reality (`app_frontmost=true`, `app_focused_window=173`). Additional decision
tracing should therefore concentrate on the remaining causality gap: sequence the
quick-terminal destruction, NSWorkspace notification, frontmost-pid transition,
focused AX-window transition, active-request completion, most recent managed
confirmation, and overlay-handoff owner.

The behavioral invariant is independent of which native component initiates the
switch: a cause-less app notification must not silently replace a newer explicit
managed-window confirmation and become command authority without corroborating
intent. For a non-flow surface close, preserving viewport position is necessary
but not sufficient; the current valid managed selection must also remain the
command target, including as the tie-breaker among zero-displacement candidates.
