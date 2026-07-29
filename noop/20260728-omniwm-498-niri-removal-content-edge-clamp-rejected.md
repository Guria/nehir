# Reject the OmniWM removal-time Niri content-edge clamp

**Verdict: no-op / do not port.** Upstream commits `a91f20e8` and `53901835`
(BarutSRB/OmniWM#498 / BarutSRB/OmniWM#499) enforce an OmniWM viewport policy
that conflicts with two intentional Nehir policies: persistent edge overscroll is
allowed, and geometry changes should preserve the user's spatial anchor with the
minimum automatic movement. A removal-time clamp to the surviving content edge
would turn an allowed parked viewport into an unsolicited post-close spring.

Verified against Nehir `main` at `62d54e16` on 2026-07-28. No Nehir source change
is warranted from these upstream commits.

## Corrected conclusion

The original upstream sweep classified the absence of a post-removal content-edge
clamp as a source-confirmed defect because Nehir's `removeWindows` /
`removeColumnByIdx` control flow matched OmniWM's pre-fix shape. That comparison
was incomplete: identical control flow does not imply identical product policy.
Nehir has deliberately diverged in what viewport positions are valid and when a
layout mutation may move the viewport.

The missing clamp is therefore not missing behavior. It is the mechanism by which
Nehir preserves the current viewport when removing a non-active column.

## Nehir policy 1: a persistent hanging edge is intentional

`ViewportState.viewportStartBounds`
(`Sources/Nehir/Core/Layout/Niri/ViewportState+Geometry.swift:600-620`) explicitly
allows persistent edge overscroll. Its source comment states that the farthest
resting positions retain only a small sliver of the edge column, and that this is
intentional even for a lone column or a strip narrower than the viewport so the
user can expose and keep viewing the desktop after releasing the trackpad.

That contract is materially wider than OmniWM's removal clamp:

```swift
let contentEdge = totalSpan - viewportSpan + gaps
let clampedStart = viewStart.clamped(
    to: min(-gaps, contentEdge) ... max(-gaps, contentEdge)
)
```

The upstream range forces the viewport back to the surviving content edge. It
cannot represent Nehir's deliberate parked positions that leave desktop visible
past the strip.

## Nehir policy 2: preserve spatial context unless movement is necessary

The existing Nehir planning record consistently treats unrequested viewport
movement as a defect:

- `completed/20260706-stable-viewport-on-window-close-recovery.md` defines a
  **maximum-stable-viewport** close policy: preserve the current view position
  when a non-active column is removed, and do not scroll across the strip during
  close recovery.
- `completed/20260701-preserve-parked-edge-snapped-anchor-across-config-relayout.md`
  preserves a reachable parked/edge-snapped anchor across relayouts rather than
  recentering it merely because geometry was recomputed.
- `discovery/20260727-column-width-cycle-recenters-viewport-multi-column.md`
  requires multi-column resizing to maximize position preservation and move only
  the minimum distance needed to keep the focused column accessible.

A close is a geometry mutation, not a viewport-navigation request. Removing a
column to the right of the active one does not change the active column's layout
coordinate or selection. Automatically moving the viewport afterward would erase
spatial context without satisfying a user request.

## Why the current removal branches are correct under that policy

`removeColumnByIdx`
(`Sources/Nehir/Core/Layout/Niri/NiriLayoutEngine+Windows.swift:471-531`) handles
three geometrically distinct cases:

1. **Removed left of active** (`removedIdx < activeIdx`): decrement the active
   index and add the removed column span to `viewOffsetPixels`. This preserves the
   same physical viewport start while column indices shift.
2. **Removed active** (`removedIdx == activeIdx`): choose the adjacent surviving
   column and run the existing automatic visibility correction when required.
3. **Removed right of active** (`removedIdx > activeIdx`): leave active index and
   viewport offset unchanged because neither the selected column nor its layout
   coordinate moved.

The third branch returning with `viewportNeedsRecalc == false` is therefore not
proof of a bug. It is the minimum-movement result for a non-active removal.
Visible desktop where the removed right-hand column used to be is allowed Nehir
behavior, not by itself evidence that the viewport is invalid.

## Existing regression coverage rejects the upstream clamp

`removalTransactionClearsPendingPreviousWhenPreviousTargetIsRemoved`
(`Tests/NehirTests/NiriLayoutEngineTests.swift:1840-1875`) provides a concrete
transaction contract:

- three 200-point columns, 8-point gap, 1000-point viewport;
- active column index 2 with `viewOffsetPixels = 0`;
- remove column index 1, left of the active column;
- after index rebasing, expect `activeColumnIndex == 1` and
  `viewOffsetPixels == 208`.

Before removal, active-column x is 416 and the viewport start is 416. After
removal, active-column x is 208 and the expected offset 208 preserves that same
viewport start of 416. A content-edge clamp would instead target viewport start
`-8`, producing offset `-216`: an unsolicited 424-point movement.

This expectation is not stale pre-fix behavior. It directly encodes the Nehir
rule that removal rebases indices without retroactively relocating the user's
viewport. The upstream clamp changes that contract.

## Why the added movement would feel delayed and uncomfortable

Both upstream versions correct the position through `animateToOffset`. In Nehir
that installs a spring when animations are enabled. The close/removal transaction
first settles its selection and index bookkeeping; the new correction then starts
a separate viewport animation toward the content edge.

The result is exactly the undesirable behavior the stability work avoids: the
window disappears, then the workspace begins moving even though the user did not
navigate. The delay is not incidental polish that can be tuned away; it is the
observable consequence of applying the wrong policy after the close transaction.
Making the correction static would remove the delay but retain the larger defect:
unrequested spatial relocation.

## Why `53901835` does not rescue the port

The follow-up narrows correction to real column removals, generalizes it to the
primary axis, carries removal evidence through refresh coalescing, and preserves
OmniWM's `centerFocusedColumn` policy. None of those changes address the policy
mismatch:

- a real column removal is still not sufficient reason to move a Nehir viewport;
- primary-axis generalization only applies the incompatible behavior more broadly;
- Nehir has no `centerFocusedColumn` setting or equivalent centering contract;
- coalescing removal evidence exists to ensure the correction runs, while the
  corrected Nehir verdict is that this correction should not run.

Do not port either the S-sized `a91f20e8` shape or the larger `53901835` follow-up.

## The initially proposed focus-follows-mouse repro was invalid

The suggested repro said to keep focus on one column, move the pointer to a
right-hand column, and close that right-hand window via its red button while
focus-follows-mouse was enabled. That cannot preserve the stated precondition:
moving the pointer over the right-hand window makes it active before the click.

Nehir's own explicit close path also raises the target before pressing its AX
close button (`WindowActionHandler.closeWindow(handle:)`,
`Sources/Nehir/Core/Controller/WindowActionHandler.swift:157-178`). Therefore a
red-button/workspace-bar close is not evidence for "removed right of active" in
the way the original instructions claimed.

An application-driven destroy could remove a non-active right-hand window, but
that only proves the branch is reachable. It does not turn the resulting exposed
desktop into a defect under Nehir's viewport policy.

## Is there any residual bug to investigate?

Not from the available evidence. The following are already covered:

- removing right of active leaves the still-selected column at the same layout
  coordinate and preserves the viewport;
- removing left of active rebases the offset to preserve the physical view start;
- removing the active column uses the existing adjacent-selection and visibility
  correction paths.

A different bug would require runtime evidence that, after removal, the selected
column becomes inaccessible or Nehir loses a coherent selection/focus state. If
such evidence appears, open a new discovery around that concrete invariant. Do
not use "desktop is visible past the surviving strip" as the failure condition,
and do not begin from OmniWM's content-edge policy.

## Decision and housekeeping

- Do not modify `NiriLayoutEngine+Windows.swift` for `a91f20e8` or `53901835`.
- Do not add a changeset, tests, or provenance entry for this port.
- Do not merge an implementation of the content-edge clamp.
- Keep BarutSRB/OmniWM#498 / BarutSRB/OmniWM#499 classified as upstream behavior
  that is not applicable to Nehir.
- The upstream sweep is corrected to remove both commits from its implementation
  recommendations.
