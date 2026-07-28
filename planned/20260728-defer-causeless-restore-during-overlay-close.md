# Defer the cause-less cross-app restore while an overlay close is resolving

**Status:** planned
**Source discovery:** `discovery/20260728-overlay-close-viewport-churn-competing-motion-actors.md`
**Related:** `discovery/20260726-browser-reactivation-overrides-new-ghostty-selection.md`
(shipped anchor this plan unblocks),
`discovery/20260728-preserve-active-viewport-can-strand-confirmed-focus-offscreen.md`
(scroll-away contract the resolved product decision leans on).

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

Fix: **defer, don't process**. A cause-less external activation that arrives
while a recognized overlay of a *different*, overlay-capable pid is visible
is held for a short resolving window. If the overlay's destroy arrives, the
deferred activation is discarded and the anchor arbitrates uncontested with
zero viewport motion. If no destroy arrives before the timeout, the
activation replays exactly as today (it was a genuine app switch).

Behaviour while the overlay is up is intentionally unchanged: the insertion
scroll to a Cmd+N window, user commands and gestures all stay live. Only the
close handoff is frozen.

## Trigger predicate (arm condition)

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

## Mechanism

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
   `reason=overlay_close_restore_discarded`, then run the anchor assert as
   today. The anchor's `activeFocusRequestToken == nil` guard
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

## Files to touch

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
  today's behaviour is already wrong more often than right. The replay path
  preserves exact current semantics.
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
   activation processes with today's exact downstream effects.
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

## Commit shape

Plain-English subjects (no Conventional Commits), e.g.:

- `Defer a cause-less restore while an overlay close is resolving`
- changeset: `mise run changeset patch "Closing an overlay terminal no longer scrolls the viewport or steals the new window's selection"`
