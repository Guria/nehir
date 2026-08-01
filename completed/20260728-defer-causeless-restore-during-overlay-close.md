# Defer the cause-less cross-app restore while an overlay close is resolving

**Status:** completed — shipped on `main` in `acbebfbd` ("Carry window identity through tab churn and steady the overlay-close focus"), `ca152b28` ("Stabilize focus arbitration around overlays and window teardown"), and `b0bca2f6` ("Harden overlay lifecycle and focus recovery"), merged 2026-07-31 via PR #193, contained in `v0.6.0-rc.43`. Moved from `planned/` to `completed/` on 2026-08-01.

**Source discovery:** [`20260728-overlay-close-viewport-churn-competing-motion-actors.md`](20260728-overlay-close-viewport-churn-competing-motion-actors.md)

**Related:** [`20260726-browser-reactivation-overrides-new-ghostty-selection.md`](20260726-browser-reactivation-overrides-new-ghostty-selection.md), [`../discovery/20260728-preserve-active-viewport-can-strand-confirmed-focus-offscreen.md`](../discovery/20260728-preserve-active-viewport-can-strand-confirmed-focus-offscreen.md), and [`../discovery/20260801-insertion-relayout-lacks-minimal-displacement-targeting.md`](../discovery/20260801-insertion-relayout-lacks-minimal-displacement-targeting.md).

All file/line references verified against the main Nehir source tree on
2026-07-28. Re-verify before editing; line numbers drift.

## TL;DR

When an overlay owner (Ghostty quick terminal) hides, it re-activates the
previously frontmost app ~60–300 ms **before** the overlay's
`AXUIElementDestroyed` arrives. Nehir processes that cause-less activation
immediately — confirming focus on the restored app, running parked-follow /
`activateWorkspace`, moving the viewport — and the resulting active focus
request silences the shipped overlay-close anchor
(`assertManagedAnchorAfterOverlayClose`, guard at
`Sources/Nehir/Core/Controller/AXEventHandler.swift:6624`).

The plan proposed deferring the whole activation and replaying it after a
250 ms deadline. That exact timer-and-payload mechanism did **not** ship.
Instead, `main` records the recognized overlay's lifecycle and treats a
cause-less cross-pid restore as provisional while the overlay is in its
pre-destroy phase: focus reality may be confirmed, but parked-workspace follow
and viewport reveal are suppressed; the recognized overlay destroy then runs
the existing close-anchor correction. A later app activation after destroy is
fresh user intent and is not delayed.

Behaviour while the overlay is up remains unchanged: insertion of a Cmd+N
window, user commands, and gestures stay live. The user confirmed on the real
reproduction that open Quick Terminal → Cmd+N → close preserves the selected
Ghostty window and does not scroll the viewport away and back.

## Landed state

The implementation is distributed across three commits on `main`:

- `acbebfbd` introduced confirmation classification, recognized-overlay
  identity, and the destroy-time anchor;
- `ca152b28` replaced generic pid-level/non-managed evidence with explicit
  overlay lifecycle, guarded pointer intent and same-app succession, and added
  the focused regression suites;
- `b0bca2f6` bounded teardown verification and made the lifecycle sampling and
  visibility checks deterministic and lazy.

The plan's `deferredOverlayCloseActivationsByOverlayPid` state, 250 ms replay
task, and "latest activation wins" payload did not ship. Avoiding that timer was
an intentional deviation: the landed code uses ordered-in state, the last
ordered-in observation, recognized overlay focus, and the destroy event as the
lifecycle boundary instead of creating another activation queue.

The user-visible release note is
`.changeset/20260729134729-closing-the-ghostty-quick-terminal-no-longer-scr.md`;
it has no contributor entry. Relevant landed tests are
`Tests/NehirTests/QuickTerminalCloseAnchorTests.swift`,
`Tests/NehirTests/QuickTerminalPointerIntentTests.swift`,
`Tests/NehirTests/QuickTerminalStartupLifecycleTests.swift`, and
`Tests/NehirTests/SameAppCloseFocusSuccessionTests.swift`. PR #193's CI ran
`mise run test` successfully (`Swift tests`, 3m38s) and passed the
`SwiftLint + SwiftFormat` check (43s).

The separate insertion-relayout minimal-displacement question did not ship in
PR #193 and is retained in
[`../discovery/20260801-insertion-relayout-lacks-minimal-displacement-targeting.md`](../discovery/20260801-insertion-relayout-lacks-minimal-displacement-targeting.md).
The Window-menu redirect remains open in
[`../discovery/20260729-window-menu-same-app-pick-redirected-to-other-apps-stable-window.md`](../discovery/20260729-window-menu-same-app-pick-redirected-to-other-apps-stable-window.md).

## Proposed trigger predicate (superseded)

All of the following, evaluated on the activation event before its downstream
processing:

1. `origin == .external` and source is app-level or window-level
   (`workspaceDidActivateApplication`, `cgsFrontAppChanged`, or
   `focusedWindowChanged`) — match what the anchor's explicit-stamp logic
   already treats as potentially cause-less (`AXEventHandler.swift:4617-4623`);
2. `selfFrontingAgeMs(for: pid) == nil` (`AXEventHandler.swift:1002`) — not
   an echo of Nehir's own fronting;
3. `requestDisposition` is `.unrelatedNoRequest` — no matching managed focus
   request;
4. a recognized overlay window of a **different** pid is currently visible:
   some `overlayPid != pid` with a non-empty
   `recognizedOverlayWindowIdsByPid[overlayPid]` (`AXEventHandler.swift:961`)
   whose recognized windowId appears in `SkyLight.shared.queryAllVisibleWindows()`
   with a non-null, non-empty frame. This is a new cross-pid helper next to
   the same-pid `hasVisibleSamePidOverlayWindow` (`AXEventHandler.swift:3177`);
   reuse its SkyLight query shape, but match by recognized windowId rather
   than by heuristics.

Note condition 4 keys on the *overlay's* pid being overlay-capable, not the
activated pid — the structural miss of
`isWithinSameAppCloseRecoveryWindow(pid:)` (`AXEventHandler.swift:6477`)
that let the restore through in every capture.

## Proposed mechanism (superseded)

Model on the existing defer-until-resolving-event pattern
(`deferredSameAppActiveNativeActivationTokens`,
`AXEventHandler.swift:3599-3613`).

1. New state in `AXEventHandler`:
   `deferredOverlayCloseActivationsByOverlayPid: [pid_t: DeferredOverlayCloseActivation]`,
   where the value records the activated pid, source, arm uptime, and a
   replay generation counter. One in-flight deferral per overlay pid;
   a second qualifying activation for the same overlay pid replaces the
   deferred payload (latest wins) without extending the deadline.
2. **Arm:** in `handleAppActivation` (`AXEventHandler.swift:3827`), after the
   self-pid early-return and `requestDisposition` computation but before any
   confirmation/recovery processing, evaluate the trigger predicate. On
   match: record the deferral, emit a `runtimeViewportTrace` record
   (`reason=overlay_close_restore_deferred`, details: activated pid, overlay
   pid, source, `selfFrontingAgeMs=nil`, disposition), schedule the timeout
   task (250 ms), and return without further processing. Nothing downstream
   runs — no `confirmManagedFocus`, no parked-follow, no
   `activateWorkspace`, no reveal — so no focus request is created and no
   retraction problem exists.
3. **Resolve on destroy:** in `handleWindowDestroyed`
   (`AXEventHandler.swift:5834`), where the destroy funnels into
   `assertManagedAnchorAfterOverlayClose` (`:5863`), first check
   `recognizedOverlayWindowIdsByPid[destroyedPid]` contains the windowId; if
   a deferral for that overlay pid exists, remove it (invalidating the
   timeout via the generation counter), emit
   `reason=overlay_close_restore_discarded`, then run the anchor assert as in
   the 2026-07-28 baseline. The anchor's `activeFocusRequestToken == nil` guard
   (`AXEventHandler.swift:6624`) is left untouched — the deferral is what
   guarantees it passes.
4. **Resolve on timeout:** if the deferral is still present after 250 ms,
   remove it and replay via
   `handleAppActivation(pid:source:origin: .retry)` with the recorded
   source, mirroring the `:3604-3612` replay. Emit
   `reason=overlay_close_restore_replayed`. The retry origin must not
   re-trip the arm predicate; guard the predicate on `origin == .external`.
5. **Hygiene:** clear the new state in both existing reset sites that clear
   the sibling deferral sets (`AXEventHandler.swift:1115-1116` region and
   `:1339-1340` region), and drop a deferral whose overlay pid terminates
   (the `:7871` overlay-capable cleanup path). Add the count to the
   `axEventHandler` memory snapshot line
   (`RuntimeDiagnosticsCoordinator.swift:751` region) like the sibling sets.

## Proposed files (superseded)

- `Sources/Nehir/Core/Controller/AXEventHandler.swift` — new state, arm
  predicate + cross-pid visible-overlay helper, deferral/resolve/replay,
  trace records, cleanup.
- `Sources/Nehir/Core/Controller/RuntimeDiagnosticsCoordinator.swift` —
  memory-snapshot count only.

## Do-not-touch fences

- `assertManagedAnchorAfterOverlayClose` and its guards — the anchor's
  semantics are correct; this plan only removes the competitor that
  pre-empted it.
- The reveal/scroll-lock policy in
  `Sources/Nehir/Core/Layout/Niri/NiriLayoutEngine+ViewportCommands.swift` —
  owned by the scroll-lock work.
- `followFocusToParkedWindowWorkspaceIfNeeded` internals — it simply never
  fires for a deferred-then-discarded activation; do not add overlay
  special-cases inside it.
- The preservation-pin machinery (`preserveActiveViewport`) — owned by
  `discovery/20260728-preserve-active-viewport-can-strand-confirmed-focus-offscreen.md`.
- Insertion-relayout scroll targeting (minimal-displacement) — explicitly a
  separate follow-up; do not bundle it here.

## Non-goals

- No freeze while the overlay is open; under-overlay behaviour is unchanged
  by design.
- No changes to overlay recognition (`ghosttyQuickTerminalOverlay` rule) or
  to `overlayCapablePids` arming.
- No tuned per-app timing beyond the single 250 ms resolving window, chosen
  to cover the observed 60–300 ms restore→destroy gap; it is a deadline for
  a race with an observed event, not a behavioural constant.

## Risks and mitigations

- **A genuine app switch during a visible overlay is delayed 250 ms.** The
  arm predicate requires a cause-less, request-less activation while a
  recognized overlay of another pid is on screen — a narrow situation where
  the 2026-07-28 baseline behavior was already wrong more often than right. The
  replay path preserves that baseline's semantics.
- **Overlay destroy never arrives (owner crashes with overlay up).** The
  timeout replays the activation; the pid-terminated cleanup drops orphaned
  deferrals.
- **Multiple overlay-capable apps.** Deferrals are keyed by overlay pid;
  destroy of one overlay resolves only its own deferral.

## Validation

Fast gate between steps and full suite at the end per repo convention
(`mise run test`). **Do not write or modify tests until the user confirms
the fix on the real repro** (`docs/TESTING.md` gate); the regression cases
below are recorded for that later phase:

1. Deferred-then-discarded: overlay visible, cause-less activation of
   another pid, overlay destroy within the window → activation never
   processed; anchor assert runs with no active request; no viewport motion.
2. Deferred-then-replayed: same arm, no destroy → after the timeout the
   activation processes with the 2026-07-28 baseline downstream effects.
3. Echo immunity: an activation with non-nil `selfFrontingAgeMs` or a
   matching request is never deferred.
4. No-overlay control: identical activation with no recognized overlay
   visible processes immediately (no deferral, no delay).

Runtime confirmation on the real repro (overlay → Cmd+N → hide), per the
discovery's validation section: `overlay_close_restore_deferred` followed by
`overlay_close_restore_discarded` and exactly one
`overlay_close_anchor_asserted`; no `decision=switch` parked-follow and no
`activateWorkspace` request for the restored app; final
`wmCommandTarget` = anchor; genuine-switch and no-new-window controls green.

## Proposed commit shape

Plain-English subjects (no Conventional Commits), e.g.:

- `Defer a cause-less restore while an overlay close is resolving`
- changeset: `mise run changeset patch "Closing an overlay terminal no longer scrolls the viewport or steals the new window's selection"`
