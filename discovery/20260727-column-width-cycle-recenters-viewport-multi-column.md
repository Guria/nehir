# Cycling column width force-recenters the focused column and moves the viewport (#170)

**Status:** source-backed root cause for #170. Verified against `main` at
`fe0596b6` on 2026-07-27. Runtime evidence proves that every width-cycle command
moves the viewport so the resized column lands exactly at the viewport center,
and that a deliberate edge-snapped position is replaced by the center snap when
the column grows.

## Executive verdict

`cycle column width forward/backward` changes the focused column's width as
requested, but the command pipeline then runs the same explicit-navigation
reveal used for focus jumps. In `revealStyle == .auto`, that reveal prefers the
center snap whenever the closest snap does not fill the viewport — which is true
for essentially every column narrower than the viewport. A width cycle therefore
almost always recenters the focused column, translating the entire scrolling
layout even though no viewport navigation was issued.

The desired behavior differs by layout class and complements the lone-window
finding in
[`20260726-lone-window-width-cycle-retains-stale-center-offset.md`](20260726-lone-window-width-cycle-retains-stale-center-offset.md):

- a centered **lone window** should track its center as width changes (that
  discovery shows it currently fails to);
- a **multi-column managed layout** should maximize position preservation —
  resize in place, keep the current viewport anchor (including deliberate edge
  snaps), and move only when the new width would otherwise leave the focused
  column inaccessible. This matches the OmniWM behavior cited in #170.

Today both classes get the wrong behavior, in opposite directions.

## Topology and identities

Single display, working viewport:

```text
viewport={{8.0,7.0},{2040.0,1251.0}}
gap=6
workspace=4 id=CE9862EF-F94E-4352-8797-C98B32B28EAE
```

Four tiled columns (canonical layout coordinates):

```text
c0 x=0.0     width=1926.3 (spec=prop:0.9500)  w2212
c1 x=1932.3  width=1011.0 (spec=prop:0.5000)  w3546
c2 x=2949.3  width=1011.0 (spec=prop:0.5000)  w3548
c3 x=3966.3  width=1926.3 (spec=prop:0.9500)  w2793 (hidden right)
```

Windows `2212`, `3546`, `3548` belong to pid 58013; `2793` belongs to pid 912.

## Runtime evidence

### 1. Every width cycle recenters the focused column

With column 1 (`w3546`) selected and `activeColumnIndex=1`, four consecutive
`toggleColumnWidth(backward)` commands produced these settled viewport states:

```text
before cmd=70:      width=1011.0  viewStart=1417.8
cmd=70 →  705.9:              →  viewStart=1265.2
cmd=71 → 1926.3:              →  viewStart=1875.4
cmd=72 → 1316.1:              →  viewStart=1570.3
cmd=73 → 1011.0:              →  viewStart=1417.8
```

Each settled position is exactly the center snap for the new width. Column 1
starts at layout x=1932.3, so its on-screen center after each command is:

```text
cmd=70: (1932.3 + 705.9/2)  - 1265.2 = 1020.05
cmd=71: (1932.3 + 1926.3/2) - 1875.4 = 1020.05
cmd=72: (1932.3 + 1316.1/2) - 1570.3 = 1020.05
cmd=73: (1932.3 + 1011.0/2) - 1417.8 = 1020.00
```

The viewport center is `2040 / 2 = 1020`. Four different widths, four different
viewport positions, one invariant: the resized column is forcibly centered. The
neighboring columns visibly translate by up to ~610 layout pixels per command
(`1265.2 → 1875.4`), which is the spatial-context loss reported in #170.

Every one of these moves is recorded as a reveal-style spring:

```text
reason=relayout.viewportOffsetChanged
lastViewportMutation=animateToOffset.spring
lastViewportMutationCaller=Nehir/ViewportState+Animation.swift:98
```

No scroll or focus-navigation command appears between the resize commands.

### 2. Growing an edge-snapped column replaces the edge snap with the center snap

In a second capture on the same workspace, column 0 (`w2212`) was selected with
the viewport deliberately parked on its left-edge snap:

```text
activeColumnIndex=0
viewStart=-6.0            (leftEdge snap = columnX - gap = 0 - 6)
w2212 cur=(14,7,...)      (screen x = 8 + 6)
```

`cmd=80` grew the column from 1316.1 to 1926.3. The viewport was moved to the
center snap:

```text
cmd=80 apply targetPixels=1926.3

relayout.viewportOffsetChanged
  currentViewStart=-6.1  targetViewStart=-56.9

scroll_animation_stop
  currentViewStart=-56.9 targetViewStart=-56.9
  w2212:selected cur=(65,7,1926,1251)
```

`-56.9` is precisely the center snap for the new width
(`0 + 1926.3/2 - 2040/2 = -56.85`). The user's explicit edge anchor was
discarded even though the left-edge snap `-6` remains a valid, reachable snap
for the new geometry and the column would have stayed fully visible there
(`0 ... 1926.3` fits inside `-6 ... 2034`).

### 3. The behavior is direction-inconsistent, confirming it is accidental

In the same capture, the immediately preceding `cmd=79` shrank the same column
from 1926.3 to 1316.1 and the edge snap survived:

```text
cmd=79 apply targetPixels=1316.1
scroll_animation_stop
  currentViewStart=-6.0 targetViewStart=-6.0
  w2212:selected cur=(14,7,1316,1251)
```

Shrink preserved the anchor; the following grow destroyed it. In the
multi-column capture above, shrink (`cmd=70`) did recenter. Whether a width
cycle preserves or discards the user's viewport position thus depends on
incidental geometry rather than any policy — there is no code path that
expresses "preserve the anchor across a resize".

## Source-backed causal chain

### 1. The width command pipeline invokes a focus-navigation reveal

`NiriLayoutHandler.cycleSize` resolves `selectedNodeId` and calls
`toggleColumnWidth`
(`Sources/Nehir/Core/Controller/NiriLayoutHandler.swift:1863-1883`).
`applyColumnWidth` installs the new spec and immediately calls
`ensureSelectionVisibleForPendingWidth`
(`Sources/Nehir/Core/Layout/Niri/NiriLayoutEngine+Sizing.swift:217-275`), which
runs:

```swift
ensureSelectionVisible(
    node: window,
    ...
    revealTrigger: .explicitNavigation
)
```

(`NiriLayoutEngine+Sizing.swift:278-318`.)

### 2. Explicit navigation unlocks fully-visible recentering

`ensureSelectionVisible` forwards to `scrollToReveal` with
`allowFullyVisibleAutomaticRecenter: revealTrigger == .explicitNavigation`
(`Sources/Nehir/Core/Layout/Niri/NiriNavigation.swift:174-250`). That flag was
designed for focus commands — after an explicit focus jump, revealing the target
even when it is already fully visible is reasonable. A width change reuses the
same trigger, so the reveal treats "user resized a column" as "user navigated to
this column".

### 3. `autoSnap` prefers the center for any non-filling column

In `scrollToReveal`, a fully visible column under `revealStyle == .auto`
resolves its target through `autoSnap()`:

```swift
func autoSnap() -> SnapPoint? {
    if let closest, context.fillsViewport(at: closest.offset, in: state) {
        return closest
    }
    return center ?? closest
}
```

(`Sources/Nehir/Core/Layout/Niri/NiriLayoutEngine+ViewportCommands.swift:92-140`.)

`fillsViewport` requires the covered span to match the viewport width within
`max(0.5, 2*gap + 0.5) = 12.5` pixels
(`Sources/Nehir/Core/Layout/Niri/ViewportState+Geometry.swift:143-203`). For a
single resized column of width 705.9, 1011, 1316.1, or 1926.3 in a 2040-pixel
viewport, no snap fills, so `autoSnap` returns the **center** snap. The reveal
then animates the viewport there:

```swift
state.animateToOffset(targetOffset, motion: motion, config: animationConfig, scale: scale)
```

This is the `animateToOffset.spring` mutation recorded after every command.

### 4. Why the current position is never considered

The fully-visible branch has exactly one anchor-preserving early-out: when the
current span *fills* the viewport, it recenters within slack and otherwise
returns. There is no branch for "the column is fully visible at a valid snap the
user chose — keep it". The current view start is used only to pick the
*closest* candidate, and `autoSnap` discards that candidate in favor of center
whenever it does not fill. The user's edge snap `-6` was the closest candidate
in the grow case and was discarded exactly this way.

## Five-why analysis

### Why 1: Why does the viewport move when cycling column width?

Because after applying the new width, the command runs a reveal that animates
the viewport to a snap for the resized column.

### Why 2: Why does that reveal move an already fully visible column?

The reveal runs with `revealTrigger: .explicitNavigation`, which sets
`allowFullyVisibleAutomaticRecenter` and bypasses the fully-visible early
return.

### Why 3: Why does it pick the center instead of the current position?

`revealStyle == .auto` resolves through `autoSnap()`, which returns the center
snap whenever the closest snap does not fill the viewport — true for every
narrower-than-viewport column.

### Why 4: Why is the user's existing anchor not an input?

The snap-selection logic only knows the candidate list and the closest-distance
heuristic. No code path records or compares "the viewport is already at a valid
snap for this column" for resize operations.

### Why 5: Why does a resize share the navigation reveal at all?

Width commands reuse `ensureSelectionVisible` for the legitimate sub-problem
"do not leave the column inaccessible after the width change", but that helper
conflates accessibility (keep it reachable/visible) with navigation intent
(bring it to the preferred snap). Resize needs only the former.

## Root cause

**`applyColumnWidth` funnels every width change through the explicit-navigation
reveal, whose `.auto` snap resolution prefers the viewport-center snap for any
column that does not fill the viewport. Width cycling therefore recenters the
focused column and moves the viewport, discarding the user's current anchor —
including deliberate edge snaps.**

## Confidence boundaries

### Confirmed

1. Four consecutive width cycles on a mid-layout column each settled with the
   column's screen center at exactly 1020 = viewport center, moving the
   viewport by up to ~610 px per command.
2. All moves are reveal springs (`animateToOffset.spring`,
   `ViewportState+Animation.swift:98`); no navigation command was issued
   between resizes.
3. Growing an edge-snapped column replaced the valid, still-reachable leftEdge
   snap (`viewStart=-6`, window x=14) with the center snap
   (`viewStart=-56.9`, window x=65).
4. The source chain `cycleSize → applyColumnWidth →
   ensureSelectionVisibleForPendingWidth → ensureSelectionVisible(.explicitNavigation)
   → scrollToReveal → autoSnap` exists on current `main` and produces exactly
   this center preference.

### Not proven

1. The precise condition under which the shrink command (`cmd=79`,
   1926.3 → 1316.1 at the left edge) preserved `-6` while the source model
   predicts a center move. The asymmetry is documented as observed; pinning the
   distinguishing gate needs targeted tracing in
   `ensureSelectionVisibleForPendingWidth`/`scrollToReveal` (log the computed
   visibility, `autoSnap` result, and the pixel-guard comparison per width
   command). This gap does not affect the root cause: the grow path and all
   four multi-column cycles demonstrate the defect directly.

## Desired behavior (per #170 and the viewport-stability principle)

1. A width cycle must not move the viewport when the focused column remains
   fully visible at the current anchor with the new width.
2. If the new width makes the current anchor invalid (column would be clipped
   or the anchor is no longer a reachable snap), move the minimum distance that
   restores validity — preserving the column's current screen-space edge where
   possible, not jumping to center.
3. Deliberate edge snaps are first-class anchors and must survive resizes that
   keep the column visible.
4. The centered **lone window** is the intentional exception: its anchor is the
   center, which must track the width change (see the companion discovery).

## Compatibility constraints for a future plan

1. Preserve the accessibility guarantee: after any width change the focused
   column must remain reachable and at least partially visible; a grown column
   wider than the remaining space still needs an adjustment.
2. Preserve genuine focus-navigation reveals (`focusTarget`, workspace-bar
   clicks) exactly as they are — the fix must distinguish resize from
   navigation, not weaken `.explicitNavigation` reveals globally.
3. Preserve `revealStyle` semantics for navigation; `auto`'s center preference
   is correct for focus jumps to offscreen columns.
4. Keep the lone-window centered policy and its width-tracking fix orthogonal;
   do not route lone-window centering through the multi-column
   anchor-preservation rule.
5. Scroll-lock behavior (`isScrollLocked`) must continue to gate automatic
   reveals.

## Investigation and fix boundary

The narrow boundary is `ensureSelectionVisibleForPendingWidth`
(`NiriLayoutEngine+Sizing.swift:278-342`): it is the only caller that runs an
explicit-navigation reveal for a width change. Candidate directions for a plan:

- introduce a dedicated `RevealTrigger`/mode for resize that keeps the current
  view start when the column stays fully visible, and otherwise clamps to the
  nearest valid snap instead of `autoSnap`;
- or compute the post-resize viewport target directly from the pre-resize
  anchor classification (left-edge / right-edge / center / unsnapped), the way
  the lone-window fix needs to carry its center anchor;
- retain `ensureColumnWidthVisible` as the accessibility backstop.

Related discoveries:

- [`20260726-lone-window-width-cycle-retains-stale-center-offset.md`](20260726-lone-window-width-cycle-retains-stale-center-offset.md)
  — the lone-window inverse: the center anchor should track width but does not.
- [`20260713-resize-command-target-offscreen-selection.md`](20260713-resize-command-target-offscreen-selection.md)
  — sizing trusts `selectedNodeId`; this discovery concerns where the viewport
  goes after sizing, not which node is sized.
