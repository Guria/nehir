# A Window-menu pick of a same-app window is redirected to another application's "stable" window

- **Status:** candidate cause identified and confirmed in source; **not**
  implemented, **not** confirmed at runtime.
- **Nehir issue:** none filed yet.
- **Source verified against:** Nehir `main` at commit `eb451326`. The capture
  quoted below was made on a build of that commit with the Ghostty
  tab-identity / overlay-focus fix set applied; none of the functions cited in
  the candidate cause are modified by that fix set, so the citations hold for
  `main` at `eb451326` as-is.

## Symptom

The user opens the application's **Window menu** and picks another window of
the same application (observed with Ghostty, whose native tabs are separate
windows and therefore all appear in the Window menu). Instead of that window
receiving focus, Nehir redirects focus to a **different application's** window
in the same workspace, then switches the workspace to follow that unrelated
window. From the user's perspective: "I picked a Ghostty window; the
workspace switched, but focus landed on Slack."

## Reproduction topology

Single display. Ghostty runs as `pid 48781`; the user's established Ghostty
window is `windowId 2750` on workspace `9E523015-…`. The picked Ghostty window
is `windowId 3220`, off-screen at pick time. A Slack window
(`pid 5831, windowId 1821` family; the redirect target below is
`windowId 121`) is a tiled column on workspace `BCE8B6DD-…`. A Ghostty quick
terminal session (overlay window `540`, recognized by the
`ghosttyQuickTerminalOverlay` rule) was opened and closed roughly six seconds
before the failing pick.

## Observed event sequence

All records from a single capture; times are the capture's own timestamps.

```text
17:59:47.085  focus_confirmed token=W(48781/2750) ws=9E523015 source=workspaceDidActivateApplication
17:59:47.599  non_managed_fallback_entered pid=48781 source=focusedWindowChanged
18:00:15.472  overlay_destroy_observed pid=48781 window=540 path=no_candidate
18:00:15.473  pending_focus_started request=41 token=W(48781/2750) reason=overlayCloseAnchorAssert
18:00:15.482  focus_confirmed token=W(48781/2750) ws=9E523015 source=focusedWindowChanged
18:00:21      ax=AXFocusedWindowChanged pid=48781 window=nil          ← Window menu opens
18:00:21.129  activation_source_observed pid=48781 source=focusedWindowChanged
18:00:21.288  activation_source_observed pid=48781 source=focusedWindowChanged  ← pick of W(48781/3220)
18:00:21      close_recovery_overlay_stable_target
                observedToken=W(48781/3220) targetToken=W(5831/121)
                recentSameAppClose=false recentNonManaged=true overlayVisible=false
                previousSameAppFocusDisappeared=false selectedSameAppFocusDisappeared=false
18:00:21.299  pending_focus_started request=42 token=W(5831/121) ws=BCE8B6DD
                reason=overlayStableRecoveryRedirect
18:00:21.340  focus_confirmed token=W(5831/121) ws=BCE8B6DD source=workspaceDidActivateApplication
18:00:21.341  follow_focus_to_parked_window token=W(5831/121) decision=switch
18:00:21.377  pending_focus_started request=43 token=W(5831/121) reason=activateWorkspace
18:00:21.398  focus_confirmed token=W(5831/121) ws=BCE8B6DD source=focusedWindowChanged
```

The `close_recovery_overlay_stable_target` record is decisive: the redirect
fired with **every** close/disappearance signal false and exactly one input
true — `recentNonManaged=true`.

## Candidate cause, in source (`main` at `eb451326`)

The redirect is `redirectToStableSameAppRecoveryFocusIfNeeded`
(`Sources/Nehir/Core/Controller/AXEventHandler.swift:3050`), invoked in its
`.overlay` phase via `redirectToStableOverlayRecoveryFocusIfNeeded` (`:3159`,
call sites `:4097` and `:4277`) when an unsolicited same-app
`focusedWindowChanged` lands on an off-screen entry. Its decision for the
`.overlay` phase (`:3081-3090`) is:

```swift
let hasOverlayRecoveryEvidence = signal.recentNonManaged || signal.overlayVisible
...
case .overlay:
    hasOverlayRecoveryEvidence
        || (recentSameAppClose
            && (previousSameAppFocusDisappeared || selectedSameAppFocusDisappeared))
```

`signal.recentNonManaged` alone is sufficient. That signal is the generic
per-pid non-managed-focus stamp
(`hasSameAppOverlayRecoverySignal`, `:2896`, reading
`hasRecentNonManagedFocus`), armed by `recordNonManagedFallbackEntered`
(`:6738`) → `recordRecentNonManagedFocus` (`:6721`) with
`recentNonManagedFocusTTL = 2` seconds (`:953`).

**Opening the application's own Window menu arms that stamp.** A menu takes
window focus away, the app emits `AXFocusedWindowChanged` with no resolvable
window (`window=nil` in the sequence above), Nehir enters the non-managed
fallback, and `non_managed_fallback_entered` records the 2-second
`recentNonManagedFocus` for the app's pid. The subsequent pick from that same
menu therefore always arrives inside its own evidence window: the menu
interaction manufactures the "overlay recovery" evidence that redirects the
pick away.

The redirect target compounds the damage:
`stableViewportFocusTarget(workspaceId:excluding:)` (`:2835`) picks the
nearest on-screen tile in the workspace excluding the observed window, with
**no requirement that the target belong to the same application** — here a
Slack window. Focus then confirms on that window and the parked-window follow
legitimately switches the workspace after it.

An adjacent comment at `:3056-3067` already documents a sibling false positive
of the same proxy (a freshly created Finder window arming
`recentNonManagedFocus` for its own pid) and exempts it via
`recentManagedAdmissionByToken`. The Window-menu pick is the same defect shape
without an exemption.

## Falsifier

The candidate cause predicts that in any capture of a failing Window-menu pick
there is a `close_recovery_overlay_stable_target` record whose
`observedToken` is the picked window, with `recentNonManaged=true` and
`recentSameAppClose=false`, `overlayVisible=false`,
`previousSameAppFocusDisappeared=false`,
`selectedSameAppFocusDisappeared=false`, preceded within
`recentNonManagedFocusTTL` (2 s) by a `non_managed_fallback_entered` record
for the same pid. The cause is **wrong** if a failing pick shows the redirect
firing with `recentNonManaged=false`, or shows no
`overlayStableRecoveryRedirect` focus request at all — the displacement would
then have a different actor.

## Proposed direction (not implemented; requires approval)

Invariant to enforce: **a same-app focus change is redirected as "overlay
recovery" only on evidence that an overlay of that application is actually in
its lifecycle, not on generic non-managed-focus residue** — the application's
own menus, popovers, and panels are non-managed focus by nature and must not
count as overlay evidence against the user's next pick.

The `.overlay` decision at `:3081-3090` should replace the
`signal.recentNonManaged` proxy with the recognized-overlay lifecycle signal
(the recognized overlay window is ordered in on screen, or its destroy was
observed within the same-app close-recovery window). The Ghostty tab-identity
fix set makes exactly this substitution in the sibling gate
`shouldSuppressSameAppInactiveWorkspaceActivationBeforeCloseRecovery`, where
the same proxy suppressed Window-menu workspace switches; this discovery
extends that correction to the redirect path. `signal.overlayVisible` and the
`recentSameAppClose && …disappeared` branch stay as they are.

Boundary cases to reason through before implementing:

1. **Genuine quick-terminal close churn** — the case the redirect exists for:
   the overlay's destroy must still qualify (it does: the destroy is observed
   for the recognized overlay window id, which arms the lifecycle signal).
2. **The `.preconfirm` phase** (`:3074-3079`) uses the same
   `hasOverlayRecoveryEvidence` but additionally requires a same-app focus
   disappearance; whether it needs the same narrowing should be decided from
   evidence, not changed alongside.
3. **`stableViewportFocusTarget` crossing application boundaries** (`:2835`)
   is a second, independent sharp edge: even a correctly triggered redirect
   can leave the user in another application. Narrowing the target to same-app
   windows is worth its own consideration and should not ride along silently.

## Explicitly out of scope

The in-app browser profile-switcher reveal failure and the browser-UI-toggle
focus jump observed in the same testing session share the "non-managed
interlude arms recovery evidence" family but flow through different gates;
they need their own discoveries. The broader design question — modeling
menus/popovers/panels as a first-class non-managed interlude instead of
per-pid evidence stamps — is the umbrella follow-up for that family.
