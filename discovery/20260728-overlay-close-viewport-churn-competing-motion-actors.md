# Quick-terminal session churns the viewport: competing motion actors with no episode owner

**Status:** actionable. Captured on 2026-07-28 against `main` with the
quick-terminal close anchor (`overlayCloseAnchorAssert`) already shipped.
Four same-day captures are inlined below; no machine-local trace is required
to follow the findings.

## Product invariant this discovery serves

Stated by the user as the primary requirement, above focus correctness:

1. **Viewport motion must be minimal** when windows are created or closed.
2. **Opening/closing an overlay window must not move the viewport at all.**
3. Commands (resize and the like) must act on the window the user is looking
   at. Focus is secondary to the two rules above.

None of the shipped mechanisms encode this invariant. Each shipped guard
suppresses one specific motion source while the others keep racing, so the
observed outcome per repro run is decided by event timing.

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
| 4 | Preservation pins | spring/gesture/close-recovery state | suppress *some* reveal passes | see [`20260728-preserve-active-viewport-can-strand-confirmed-focus-offscreen.md`](20260728-preserve-active-viewport-can-strand-confirmed-focus-offscreen.md) — a Boolean gate with no completion contract |

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

## Repair direction: the overlay session as a viewport transaction

Model the episode explicitly. Boundaries are already observable:

- **Open:** a recognized overlay window of an overlay-capable pid becomes
  frontmost (`recognizedOverlayWindowIdsByPid`, `overlayCapablePids` —
  `AXEventHandler.swift:955-961`, `:3218-3235`).
- **Close:** `AXUIElementDestroyed` of that overlay window, plus settle of
  the anchor assert's own confirmation echoes.

Within the episode:

1. **Freeze programmatic viewport motion.** Insertion relayout scroll,
   parked-follow workspace activation, `activateWorkspace` scrolls and
   confirm-pass reveals are all deferred or dropped. User-initiated gestures
   remain live — the freeze applies to Nehir-ordered motion only. A window
   created during the episode is inserted into the strip without scrolling to
   it (it is under the overlay anyway).
2. **One arbitration at close.** Selection and `wmCommandTarget` go to the
   anchor (the shipped explicit-stamp logic already picks the right token in
   every capture). Deferred motion orders from the episode are discarded, not
   replayed.
3. **At most one minimal reveal.** If — and only if — the anchor's column is
   not visible in the frozen viewport, run a single reveal with a
   minimal-displacement snap (nearest edge, never a farther "style" snap).
   If it is visible (Capture B's right-edge-pinned terminal), zero motion.
4. **Retraction.** Winning the arbitration must cancel the losers' queued
   requests (the Capture D `activateWorkspace` follow-up), not merely race
   them.

Independently of the episode mechanism, the insertion relayout scroll should
adopt minimal-displacement targeting in general — Capture B shows it moving a
full column width when the inserted column was already flush with the right
screen edge.

### Open product decision

Rule 2 of the invariant ("overlay close moves nothing") conflicts with rule 3
("commands act on what the user sees") exactly when the anchor column ends the
episode outside the frozen viewport. The direction above resolves it with one
minimal reveal, treating "focused and selected but invisible" as the worse
outcome (per Capture D). If strict zero motion is preferred instead, the
arbitration would have to hand selection to the anchor while leaving the
viewport untouched — accepting an off-screen command target by design. This
choice gates the plan and needs an explicit call.

## Validation requirements

A validating capture of the full repro (overlay open → Cmd+N → overlay hide)
must show, for the whole episode:

1. no `scroll_animation_start` between overlay open and overlay destroy whose
   source is Nehir-ordered (insertion relayout, activateWorkspace,
   parked-follow);
2. exactly one `overlay_close_anchor_asserted` after the destroy, with no
   competing `pending_focus_started` surviving it;
3. at most one post-close scroll, and only when the anchor column was not
   visible; its displacement must be the minimal snap distance;
4. final `wmCommandTarget`, layout selection and confirmed focus all equal to
   the anchor token; and
5. a subsequent resize command applying to the anchor's column while that
   column is on-screen.

The no-new-window control (open and hide the overlay without Cmd+N) must show
zero viewport motion and zero focus-request churn for the entire episode.

## Relationships

- [`20260726-browser-reactivation-overrides-new-ghostty-selection.md`](20260726-browser-reactivation-overrides-new-ghostty-selection.md)
  established the cause-less restore mechanism and shipped the anchor.
  Capture A here shows the anchor being pre-empted by Nehir's own reaction to
  that restore; its "fixed and confirmed" status holds only for the topology
  where the user's window stays on-screen.
- [`20260728-preserve-active-viewport-can-strand-confirmed-focus-offscreen.md`](20260728-preserve-active-viewport-can-strand-confirmed-focus-offscreen.md)
  documents actor 4's structural defect (suppression without a completion
  contract). The episode transaction proposed here is the "single accountable
  owner" that discovery's repair boundary calls for, applied to the overlay
  shape.
- [`20260702-quick-terminal-close-reveals-managed-ghostty-column.md`](20260702-quick-terminal-close-reveals-managed-ghostty-column.md)
  is the earliest same-shape finding: overlay close causing an unwanted
  reveal of a managed column.
- [`../completed/20260706-stable-viewport-on-window-close-recovery.md`](../completed/20260706-stable-viewport-on-window-close-recovery.md)
  owns the close-recovery pins that partially (and insufficiently) protect
  the viewport in Captures B–D.
