# Quick-terminal session churns the viewport: competing motion actors with no episode owner

**Status:** completed — shipped on `main` in `acbebfbd` ("Carry window identity through tab churn and steady the overlay-close focus"), `ca152b28` ("Stabilize focus arbitration around overlays and window teardown"), and `b0bca2f6` ("Harden overlay lifecycle and focus recovery"), merged 2026-07-31 via PR #193, contained in `v0.6.0-rc.43`. The user confirmed the Quick Terminal → Cmd+N → close reproduction before merge. Moved from `discovery/` to `completed/` on 2026-08-01.

Four captures from 2026-07-28 remain inlined below; no machine-local trace is
required to follow the findings.

## Product invariant this discovery serves

Stated by the user as the primary requirement, above focus correctness:

1. **Viewport motion must be minimal** when windows are created or closed.
2. **Opening/closing an overlay window must not move the viewport at all.**
3. Commands (resize and the like) must act on the window the user is looking
   at. Focus is secondary to the two rules above.

At the 2026-07-28 `main` state captured by this discovery, no mechanism encoded this
invariant. Each guard suppressed one motion source while the others kept
racing, so the observed outcome varied with event timing.

## Landed state

PR #193 did not implement the companion plan's 250 ms deferred-activation
queue. The landed mechanism instead makes the recognized overlay lifecycle the
shared evidence boundary:

- recognized overlay window ids and ordered-in/destroy observations define a
  `beforeDestroy` / `recentlyDestroyed` lifecycle;
- a cause-less cross-pid restore during `beforeDestroy` cannot trigger a parked
  workspace follow or viewport reveal;
- the recognized overlay destroy runs the existing anchor correction against
  the newest explicit managed confirmation;
- a later activation after destroy is handled as fresh user intent;
- same-app focus succession probes the predecessor's AX liveness before
  accepting and revealing a successor, preserving ordinary same-app switches
  while preventing a close-selected far window from moving the viewport.

This differs from the selected repair direction below: confirmation can record
native focus reality, but the harmful follow/reveal effects are withheld. No
`deferredOverlayCloseActivationsByOverlayPid`, replay payload, or new 250 ms
behavioral deadline exists on `main`.

The user confirmed that open Quick Terminal → Cmd+N → close leaves focus and the
viewport on the intended Ghostty window. They also confirmed that closing a
window whose app immediately selects an off-screen same-app successor no longer
moves the viewport there, while ordinary same-app window/profile switches still
work.

The release note is
`.changeset/20260729134729-closing-the-ghostty-quick-terminal-no-longer-scr.md`
with no contributor entry. Relevant tests landed in
`Tests/NehirTests/QuickTerminalCloseAnchorTests.swift`,
`Tests/NehirTests/QuickTerminalPointerIntentTests.swift`,
`Tests/NehirTests/QuickTerminalStartupLifecycleTests.swift`, and
`Tests/NehirTests/SameAppCloseFocusSuccessionTests.swift`. PR #193's CI ran
`mise run test` successfully (`Swift tests`, 3m38s) and passed
`SwiftLint + SwiftFormat` (43s).

The insertion-relayout actor was deliberately left unchanged and is now tracked
separately in
[`../discovery/20260801-insertion-relayout-lacks-minimal-displacement-targeting.md`](../discovery/20260801-insertion-relayout-lacks-minimal-displacement-targeting.md).
The Window-menu redirect remains open in
[`../discovery/20260729-window-menu-same-app-pick-redirected-to-other-apps-stable-window.md`](../discovery/20260729-window-menu-same-app-pick-redirected-to-other-apps-stable-window.md).

## Common topology of all four captures

- Internal display 2056×1329, workspace viewport ≈ 2040 pt wide.
- Helium browser, pid 58013 — the app that was frontmost before the quick
  terminal opened. Its window (13250 in Capture A, 13799 in B–D) sits in a
  1316 pt column.
- Ghostty, pid 912. Its quick-terminal overlay is windowId 124, recognized as
  `builtInRule(ghosttyQuickTerminalOverlay)` `disposition=unmanaged`.
- The repro: open the quick terminal over the browser, press Cmd+N to create
  a regular Ghostty window (admitted as a new tiled column), then hide the
  quick terminal. Ghostty's `QuickTerminalController` restores the previously
  frontmost app on hide; that restore arrives as a cause-less external
  activation (`self_fronting_age_ms=nil`) — the premise of
  [`20260726-browser-reactivation-overrides-new-ghostty-selection.md`](20260726-browser-reactivation-overrides-new-ghostty-selection.md).

## The competing motion actors

During the ~1.5 s after the quick terminal hides, the viewport and selection
are written by four independent actors:

| # | Actor | Trigger | Motion it orders | Shipped guard that does NOT stop it |
| - | ----- | ------- | ---------------- | ----------------------------------- |
| 1 | Column-insertion relayout | new window admitted (`layoutRefreshRememberedFocus` request) | scroll to the new column's snap | reveal pins gate only `scrollToReveal`, not relayout scroll |
| 2 | Cause-less restore + parked-follow | Ghostty's on-hide re-activation of the browser | `followFocusToParkedWindowWorkspaceIfNeeded` → `activateWorkspace` scroll + reveal | `isWithinSameAppCloseRecoveryWindow(pid:)` keys on the browser's pid; close evidence is on Ghostty's pid (`AXEventHandler.swift:6477`) |
| 3 | Overlay-close anchor | destroy of recognized overlay window (`AXEventHandler.swift:6616`) | its own focus request (+ its reveal) | yields to any active focus request (`activeFocusRequestToken == nil` guard, `AXEventHandler.swift:6624`) — including one opened by actor 2 |
| 4 | Preservation pins | spring/gesture/close-recovery state | suppress *some* reveal passes | see [`../discovery/20260728-preserve-active-viewport-can-strand-confirmed-focus-offscreen.md`](../discovery/20260728-preserve-active-viewport-can-strand-confirmed-focus-offscreen.md) — a Boolean gate with no completion contract |

Which actor wins the viewport, which wins OS focus, and which wins the layout
selection/command target is a per-run race. The four captures below are four
different outcomes of the same race.

## Capture A — the anchor is silenced by the race it was built to correct

The browser window here is 58013:13250; the new Ghostty window is 912:13751.
The viewport had scrolled to the new Ghostty column
(`currentViewStart=7011.3`), pushing the browser column off-screen left.

```text
t=12:27:00.166 activation_source_observed pid=58013 source=workspaceDidActivateApplication self_fronting_age_ms=nil
t=12:27:00.183 focus_confirmed token=58013:13250
t=12:27:00.188 focus_reality   token=58013:13250 observed_focused=false on_screen=false app_frontmost=true
t=12:27:00.188 follow_focus_to_parked_window token=58013:13250 decision=switch
t=12:27:00.224 pending_focus_started request=73 token=58013:13250 reason=activateWorkspace
t=12:27:00.243 create_seen window=124            ← overlay teardown events begin
2026-07-28T12:27:00Z ax=AXUIElementDestroyed pid=912 window=124
```

No `overlay_close_anchor_asserted` record exists for this destroy. The assert
returns early at its first guard because request 73 — opened 20 ms earlier by
actor 2 — is still active. The anchor's own memory was correct: the explicit
stamp had refused the cause-less browser confirmation
(`causelessExternalConfirmation`, `AXEventHandler.swift:4617-4623`) and still
named 912:13751. It was never consulted.

The deferred parked-follow then revealed the browser:

```text
reason=ax_focus_confirm_reveal_result token=58013:13250 columnIndex=4 didReveal=true
reason=relayout.viewportOffsetChanged currentViewStart=7010.8 targetViewStart=5841.8
```

Outcome: viewport scrolled ~1170 pt away from the just-created window; focus,
selection and `wmCommandTarget` all landed on the browser. The exact theft the
anchor shipped to prevent, executed by Nehir's own follow-up to the theft.

## Capture B — correct final focus, yet the viewport still moved ~1000 pt

Browser 58013:13799, new Ghostty window 912:13993, admitted while the
viewport rested at `currentViewStart=5180.7` with the browser column fully
visible and the strip's last column pinned at the right screen edge.

Insertion relayout (actor 1) ordered the scroll:

```text
t=12:54:10.972 relayout_activated_window token=912:13993
t=12:54:10.972 pending_focus_started request=154 token=912:13993 reason=layoutRefreshRememberedFocus
reason=scroll_animation_start currentViewStart=5288.8 targetViewStart=6197.7
```

Every reveal pass for 13993 was skipped by pins
(`spring_in_flight`, then `close_recovery_pin`), i.e. actor 4 suppressed the
*reveal* engine while the *relayout* scroll — the actual 1017 pt of motion —
ran to completion. The anchor (actor 3) fired twice and correctly converged
selection on 13993 (`anchorSource=explicit_stamp`, `anchor=912:13993`).

Outcome: focus/selection correct, but the viewport travelled a full column
width for a window that was already reachable with zero or near-zero motion.
The reveal engine's minimal-motion knowledge (`closest` snap) never applied
because the motion came from a code path that has no minimal-motion policy.

## Capture C — browser pushed half off-screen; resize correctly follows the terminal

Browser 58013:13799 (column 6), new Ghostty window 912:14117 (column 7).
Sequence of viewport writes within ~4 s:

```text
reason=scroll_animation_start currentViewStart=7630.5 targetViewStart=9045.3   ← insertion relayout (actor 1)
reason=ax_focus_confirm_reveal_result token=58013:13799 didReveal=true         ← browser restore reveal (actor 2)
reason=scroll_animation_start currentViewStart=9041.1 targetViewStart=7875.8
t=12:58:32.129 pending_focus_started request=207 token=912:14117 reason=overlayCloseAnchorAssert   ← actor 3 re-asserts
reason=scroll_animation_stop currentViewStart=7875.8
... user resize commands ...
cmd=20 apply kind=toggleColumnWidth(forward) columnIndex=7 previous=1011.0 targetPixels=1316.1
cmd=21 apply kind=toggleColumnWidth(forward) columnIndex=7 previous=1316.1 targetPixels=1926.3
final wmCommandTarget=912:14117 wmCommandTargetSource=layoutSelection
```

Outcome: ~1400 pt of round-trip motion (right for the insertion, left for the
browser restore), settling with the browser only partially visible. The anchor
did win selection this time, so resize hit the terminal — correct target, but
the user is looking at a half-visible browser the system scrolled to and away
from within two seconds.

## Capture D — three-way split: viewport at the browser, resize into an off-screen terminal

Browser 58013:13799 (column 6), new Ghostty window 912:14461 (column 7).
The decisive second, 13:16:43:

```text
t=.038 activation_source_observed pid=58013 source=workspaceDidActivateApplication self_fronting_age_ms=nil
t=.093 focus_confirmed token=58013:13799
t=.094 follow_focus_to_parked_window token=58013:13799 decision=switch          ← actor 2 arms
t=.122 pending_focus_started request=335 token=912:14461 reason=overlayCloseAnchorAssert   ← actor 3 fires first this time
t=.237 pending_focus_started request=336 token=58013:13799 reason=activateWorkspace        ← actor 2's deferred switch lands anyway
reason=ax_focus_confirm_reveal_result token=58013:13799 columnIndex=6 didReveal=true       ← viewport goes to the browser
t=.423 focus_confirmed token=912:14461 source=workspaceDidActivateApplication self_fronting_age_ms=293
reason=ax_focus_confirm_reveal_skipped token=912:14461 preserveActiveViewportReason=close_recovery_pin
```

Final state, ~1 s later:

```text
cmd=39 apply kind=toggleColumnWidth(forward) columnIndex=7 previous=1011.0 targetPixels=1316.1
wmCommandTarget=WindowToken(pid: 912, windowId: 14461) wmCommandTargetSource=layoutSelection
```

Outcome: the viewport shows the browser; the user-facing frontmost app is the
browser; the layout selection and command target are the terminal, whose
column sits entirely outside the viewport; the resize command visibly did
nothing (it resized the off-screen terminal). Actors 2 and 3 each won half of
the state — the split-brain form of the original resize-target complaint.

## Root cause

There is no owner of viewport motion for the overlay session. Each mechanism
was added to counter one specific misbehaviour (theft → anchor; chasing a
successor → close-recovery windows; reveal churn → pins), and each keys its
guards on its own trigger (pid of the incoming event, presence of *any*
focus request, spring state). The invariant the user actually wants —
"an overlay session produces at most one, minimal, viewport adjustment, and
selection/commands end on the anchor" — is a property of the whole episode,
not of any single event, and nothing in the code models the episode.

Two independent sub-defects compound it:

1. **Insertion relayout has no minimal-motion policy.** The
   `layoutRefreshRememberedFocus` scroll targets a snap (left-edge of a
   neighbouring column in Capture B) without asking whether the new column is
   already visible or reachable with less motion. The reveal engine's
   `closest`-snap knowledge lives only in `scrollToReveal`, which the pins
   suppress anyway.
2. **The anchor is subordinate to the race it arbitrates.** Its
   `activeFocusRequestToken == nil` guard (`AXEventHandler.swift:6624`) makes
   it yield to a request opened milliseconds earlier by the very cause-less
   restore it exists to correct (Capture A), and when it does fire, nothing
   retracts the loser's already-queued work (Capture D's request 336).

## Repair direction selected on 2026-07-28 (superseded in implementation)

An earlier draft of this section proposed freezing Nehir-ordered viewport
motion for the whole overlay session (from overlay-frontmost to destroy).
The user rejected that scope: while the overlay is up, everything must behave
as in the 2026-07-28 baseline — the insertion relayout scroll to a Cmd+N
window, user commands and swipes all stay live. The freeze applies only to the **close handoff**.

That works because the close has an observable early edge. In all four
captures the first close event is not the overlay's destroy but the owner's
cause-less restore: an external activation of a *different* pid with
`self_fronting_age_ms=nil` and `requestDisposition=unrelatedNoRequest`,
arriving while a recognized overlay window of an overlay-capable pid is
visible and frontmost. The destroy follows 60–300 ms later. Arming on the
destroy itself would be too late — Capture A's harmful
`follow_parked → activateWorkspace` started ~60 ms before the destroy
arrived.

The mechanism, an application of the existing defer-until-resolving-event
pattern (`deferredSameAppActiveNativeActivationTokens`,
`AXEventHandler.swift:3599-3613`, 120 ms replay) to the cross-app overlay
handoff:

1. **Arm** on the cause-less external activation while a recognized overlay
   of an overlay-capable pid is visible. Defer the activation's downstream
   processing — parked-follow, `activateWorkspace`, confirm-pass reveal —
   instead of executing it.
2. **Resolve on overlay destroy** (this was the terminal hiding): discard the
   deferred work entirely; the anchor assert
   (`assertManagedAnchorAfterOverlayClose`, `AXEventHandler.swift:6616`)
   runs without a competing `activeFocusRequestToken` and lands selection,
   `wmCommandTarget` and focus on the stamped token. Because the insertion
   scroll already ran under the overlay, the anchor column is normally
   visible → zero motion at close.
3. **Resolve on timeout** (~200–300 ms, no destroy): this was a genuine
   click/Cmd-Tab to another app; replay the deferred activation as in the
   2026-07-28 baseline. Cost: an imperceptible delay on a real app switch that
   happens to race an open overlay.
4. **Retraction stays required**: arming must also prevent (or resolution
   must cancel) queued follow-ups from the deferred activation — Capture D's
   surviving `activateWorkspace` request is the counterexample.

Expected outcome per capture: A and D — the restore is deferred and
discarded, the anchor wins uncontested, zero close motion, no split-brain;
B and C — the browser-restore round-trip disappears, leaving only the
under-overlay insertion scroll.

Independently of the episode mechanism, Capture B established that insertion
relayout lacked minimal-displacement targeting: it moved a full column width
when the inserted column was already flush with the right screen edge. PR #193
did not change that path; the retained follow-up is
[`../discovery/20260801-insertion-relayout-lacks-minimal-displacement-targeting.md`](../discovery/20260801-insertion-relayout-lacks-minimal-displacement-targeting.md).

### Product decision (resolved)

Because the insertion scroll still runs under the overlay, the anchor column
is normally already visible when the overlay closes, so "zero motion at
close" and "commands act on what the user sees" coincide in the standard
Cmd+N flow. The residual case — the user manually scrolled away from the
anchor during the overlay session — is resolved in favour of **zero motion**:
the user just expressed a viewport preference, and snapping back would be the
churn this work removes. The anchor still takes selection and focus;
[`../discovery/20260728-preserve-active-viewport-can-strand-confirmed-focus-offscreen.md`](../discovery/20260728-preserve-active-viewport-can-strand-confirmed-focus-offscreen.md)'s
scroll-away contract already covers this shape. The no-new-window control
(open and hide without Cmd+N) is strict zero motion throughout.

## Pre-merge validation contract

The pre-merge validation contract for the full reproduction (overlay open →
Cmd+N → overlay hide) required:

1. under the overlay, behavior unchanged from the 2026-07-28 baseline: the insertion scroll to
   the Cmd+N column runs, and user commands/gestures act normally;
2. the cause-less restore is deferred, not processed: no
   `follow_focus_to_parked_window … decision=switch` and no
   `pending_focus_started … reason=activateWorkspace` for the restored app
   between the restore activation and the overlay destroy;
3. exactly one `overlay_close_anchor_asserted` after the destroy, with no
   competing `pending_focus_started` surviving it;
4. zero Nehir-ordered viewport motion from the restore activation to episode
   settle (the anchor column is already visible from the insertion scroll);
5. final `wmCommandTarget`, layout selection and confirmed focus all equal to
   the anchor token, and a subsequent resize command applying to the anchor's
   on-screen column.

Controls:

- **No new window** (open and hide without Cmd+N): zero viewport motion and
  zero focus-request churn for the entire episode; the deferred restore is
  discarded and the anchor no-ops on the preserved pre-overlay token.
- **Genuine app switch racing an overlay**: click/Cmd-Tab to another app
  while the overlay is visible and no destroy follows — the deferred
  activation was required to replay after the timeout and reproduce the
  2026-07-28 baseline behavior (confirmation, reveal, workspace activation as
  applicable).
- **Manual scroll-away during overlay, then close**: viewport stays where the
  user put it; the anchor takes selection/focus without a snap-back reveal.

## Relationships

- [`20260726-browser-reactivation-overrides-new-ghostty-selection.md`](20260726-browser-reactivation-overrides-new-ghostty-selection.md)
  established the cause-less restore mechanism and shipped the anchor.
  Capture A here shows the anchor being pre-empted by Nehir's own reaction to
  that restore; its "fixed and confirmed" status holds only for the topology
  where the user's window stays on-screen.
- [`../discovery/20260728-preserve-active-viewport-can-strand-confirmed-focus-offscreen.md`](../discovery/20260728-preserve-active-viewport-can-strand-confirmed-focus-offscreen.md)
  documents actor 4's structural defect (suppression without a completion
  contract). The episode transaction proposed here is the "single accountable
  owner" that discovery's repair boundary calls for, applied to the overlay
  shape.
- [`20260702-quick-terminal-close-reveals-managed-ghostty-column.md`](20260702-quick-terminal-close-reveals-managed-ghostty-column.md)
  is the earliest same-shape finding: overlay close causing an unwanted
  reveal of a managed column.
- [`20260706-stable-viewport-on-window-close-recovery.md`](20260706-stable-viewport-on-window-close-recovery.md)
  owns the close-recovery pins that partially (and insufficiently) protect
  the viewport in Captures B–D.
