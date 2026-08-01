# Insertion relayout lacks minimal-displacement viewport targeting

**Status:** discovery — observed during PR #193 runtime validation on 2026-07-31;
not changed by the commits contained in `v0.6.0-rc.43`. Recorded as a separate
follow-up on 2026-08-01.

## Observation

During the PR #193 insertion/overlay validation, a relayout moved the viewport
by approximately 1,017 points even though the selected column was already
visible and flush with the right edge of the screen. The captured layout had
adjacent column origins at `0.0`, `1017.0`, and `2034.0`, with cached column
width `1011.0`; the motion therefore amounted to one complete column pitch
rather than the smallest displacement needed to keep the selected column
visible.

This observation is distinct from the overlay-close arbitration corrected by PR
#193. The overlay lifecycle and focus anchor selected the intended managed
window, but the later insertion relayout still chose a viewport target that
moved by a full column pitch.

## Source boundary

`LayoutRefreshController.applyAnimationDirectives` handles an
`.activateWindow(token)` directive by recording `relayout_activated_window` and
calling:

```swift
controller.focusWindow(token, reason: .layoutRefreshRememberedFocus)
```

That call is at
`Sources/Nehir/Core/Controller/LayoutRefreshController.swift:709-721`. The
directive carries only the target token; it does not carry a viewport-placement
policy or a maximum permitted displacement.

The Niri viewport layer already has minimum-distance information in
`scrollToReveal`. It computes the target column's snap candidates and selects
`closest(to: viewStart)` at
`Sources/Nehir/Core/Layout/Niri/NiriLayoutEngine+ViewportCommands.swift:138-146`;
for `.closest` reveal style, that candidate is used directly at lines 178-186.
The insertion-relayout activation boundary does not explicitly require that
closest-snap policy.

## Candidate policy gap

**Hypothesis:** remembered-focus activation after insertion/reconciliation can
enter the ordinary focus/reveal pipeline without preserving the relayout's
pre-motion viewport position or constraining the reveal to the least-displacing
valid snap. A later focus step can therefore choose a valid but farther target
even when the selected column is already visible at an edge.

The hypothesis would be disproven if a reproduction shows that the 1,017-point
motion was scheduled before `.relayoutActivatedWindow`, or that the remembered
focus path already selected the nearest valid snap and a separate animation
rewrote the target afterward. Any implementation work should first add enough
decision evidence to identify the directive, target token, visibility, candidate
snaps, viewport start, and chosen target in one durable event sequence.

## Required invariant

Insertion/reconciliation may restore remembered focus, but it should not move
the viewport when the target is already fully visible and the existing viewport
is a valid placement. When movement is required, it should select the valid
placement with the smallest displacement from the pre-relayout viewport start,
unless an explicit navigation policy requests centering.

The policy must be derived from viewport geometry and snap candidates, not from
a timing delay or a literal distance tuned to the 1,017-point observation.

## Boundary cases for a future plan

- one column, where no viewport motion should be introduced;
- several columns with the target fully visible at either viewport edge;
- a clipped target, where the minimum motion that restores the required
  visibility should win;
- a fully parked target, which still must be revealed;
- column widths and gaps that differ from the observed `1011 + 6` geometry;
- monitors with different viewport widths and display scales;
- an active spring or gesture, so insertion targeting does not strand confirmed
  focus off-screen or overwrite explicit navigation;
- explicit navigation, whose centering/reveal policy must remain distinguishable
  from background remembered-focus restoration.

## Scope relationship

PR #193 intentionally left this viewport-targeting policy unchanged. Its landed
state is recorded in
[`../completed/20260731-pr-193-ghostty-tab-identity-and-overlay-focus.md`](../completed/20260731-pr-193-ghostty-tab-identity-and-overlay-focus.md).
The overlay-close investigation that exposed the independent motion actor is in
[`../completed/20260728-overlay-close-viewport-churn-competing-motion-actors.md`](../completed/20260728-overlay-close-viewport-churn-competing-motion-actors.md),
and the superseded deferred-activation plan is in
[`../completed/20260728-defer-causeless-restore-during-overlay-close.md`](../completed/20260728-defer-causeless-restore-during-overlay-close.md).
