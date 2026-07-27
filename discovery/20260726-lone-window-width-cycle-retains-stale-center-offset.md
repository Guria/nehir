# Lone-window width cycling retains the previous center offset and pins the window to its old x-position

**Status:** source-backed root cause. Verified against `main` at `fe0596b6` on
2026-07-26. Companion to #170 (multi-column width-cycle recentering); see the
relationship section below. The runtime evidence proves that Nehir itself keeps the previous
viewport offset and continues requesting the old x-position while the lone column
widens. The later AX verification mismatch is a consequence of that invalid target,
not the primary centering defect.

## Executive verdict

A lone Helium window was correctly centered at `x=212` while its width was 1632
pixels in a 2040-pixel working viewport. Cycling its width from the 65% preset to
the 95% preset changed the requested width to 1926.3 pixels, but left both
`currentOffset` and `targetOffset` at `-204`. Nehir therefore continued requesting
`x=212` instead of recomputing the centered x-position near 65.

The source-level defect is a two-stage stale-geometry handoff:

1. `applyColumnWidth` marks the lone column as manually sized but leaves its old
   `loneWindowLayoutWidthOverride` installed while it immediately asks viewport
   logic to reveal/recenter the pending width.
2. Viewport snap calculations use `effectiveViewportWidth`, which prefers that old
   override over the temporarily installed target `cachedWidth`. The fit pass still
   sees the old 1632-pixel geometry and concludes that offset `-204` is already the
   correct center.
3. A later layout pass clears the override, but its width-change detector compares
   the new geometry with the already-mutated `cachedWidth`. Those values advance
   together during the width animation, so the detector does not recognize the
   explicit width command and never resets the lone-window viewport center.

The widening column is consequently rendered around the old anchor. At `x=212`,
the display's right edge at 2056 allows only `2056 - 212 = 1844` pixels, exactly
the final observed AX width. The repeated `verificationMismatch` records are thus
consistent with the native window being clamped at the screen edge after Nehir
requested an offscreen frame.

## Topology and expected geometry

Relevant display and working viewport:

```text
display frame=(0,0 2056x1329)
working viewport x=8 ... 2048
working viewport width=2040
```

Lone managed window:

```text
token=WindowToken(pid: 79206, windowId: 173)
bundleId=net.imput.helium
workspace=3FCEFFBA-2C76-4DA3-ACB8-1CAD2FC3A64E
columns=1
activeColumnIndex=0
selected=w173
```

Before the width command, the window is 1632 pixels wide and correctly centered:

```text
currentOffset=-204.0
targetOffset=-204.0
cur=(212,7 1632x1251)
target=(212,7 1632x1251)
live=(212,7 1632x1251)
```

The geometry checks:

```text
horizontal slack = 2040 - 1632 = 408
half slack = 204
centered x = workingMinX + halfSlack = 8 + 204 = 212
```

Cycling forward selects the 95% width preset:

```text
previous=1316.1
currentSpec=proportion(0.6500)
newSpec=proportion(0.9500)
targetPixels=1926.3
```

The correct centered geometry for 1926.3 pixels would be:

```text
horizontal slack = 2040 - 1926.3 = 113.7
half slack = 56.85
expected center offset = (1926.3 - 2040) / 2 = -56.85
expected x = 8 - (-56.85) = 64.85, approximately 65
```

## Runtime sequence

### 1. The command starts from a policy width override

At command start, the column carries two different width representations:

```text
cached=1316.1
override=1632.0
spec=proportion(0.6500)
manual=false
frame=1632.0
currentOffset=-204.0
targetOffset=-204.0
```

The 1632-pixel override is the resolved centered-lone-window policy width. The
underlying 65% column spec resolves to 1316.1 pixels, but the policy override is
what layout and viewport visibility currently use.

### 2. The width changes but the viewport target does not

The command applies `proportion(0.9500)` and starts an animation toward 1926.3:

```text
cmd=9 apply kind=toggleColumnWidth(forward)
targetPixels=1926.3
newSpec=proportion(0.9500)
presetIdx=3
didStartAnimation=true
```

The first viewport record after the command already shows that the manual width
has been adopted while the old center remains untouched:

```text
cached=1316.1
override=nil
spec=proportion(0.9500)
target=1926.3
manual=true
anim=1316.9->1926.3
currentOffset=-204.0
targetOffset=-204.0
cur=(212,7 1316x1251)
target=(212,7 1316x1251)
```

As the width reaches approximately 1848 pixels, the same stale anchor remains:

```text
cached=1847.7
spec=proportion(0.9500)
currentOffset=-204.0
targetOffset=-204.0
cur=(212,7 1848x1251)
target=(212,7 1848x1251)
```

At animation completion, Nehir's own target is still wrong:

```text
cached=1926.3
spec=proportion(0.9500)
currentOffset=-204.0
targetOffset=-204.0
cur=(212,7 1926x1251)
target=(212,7 1926x1251)
live=(212,7 1844x1251)
```

This rules out an AX-only positioning error. The layout target itself retains
`x=212`; no viewport mutation attempts to move it toward the correct centered
position near `x=65`.

### 3. Native frame application stops at the display edge

Frame application repeatedly requests widths up to approximately 1926 while
keeping `x=212`:

```text
target=(212,7 1912.5x1251) observed=(212,7 1844x1251)
target=(212,7 1920.0x1251) observed=(212,7 1844x1251)
target=(212,7 1926.5x1251) observed=(212,7 1844x1251)
reason=verificationMismatch
```

The observed maximum is not arbitrary:

```text
212 + 1844 = 2056
```

That is the display's exact right edge. The requested final frame would instead
end at approximately `212 + 1926 = 2138`, 82 pixels beyond the display. The
verification mismatch is therefore downstream evidence of the stale x-position:
macOS or the application keeps the window within the containing display while
Nehir continues asking for an offscreen frame.

## Source-backed causal chain

### 1. Manual width activation does not clear the old lone-window override

`applyColumnWidth` installs the new width spec and marks the column as manually
sized:

```swift
column.width = newWidth
column.presetWidthIdx = presetIndex
column.isFullWidth = false
column.savedWidth = nil
column.hasManualSingleWindowWidthOverride = true
```

It then immediately calls `ensureSelectionVisibleForPendingWidth`
(`Sources/Nehir/Core/Layout/Niri/NiriLayoutEngine+Sizing.swift:217-275`). There is
no call to `clearLoneWindowLayoutWidthOverride()` before the viewport fit.

### 2. The pending-width fit mutates `cachedWidth`, but snap geometry ignores it

For an animated width change, `ensureSelectionVisibleForPendingWidth` temporarily
sets the column's `cachedWidth` to the 1926.3-pixel target, performs reveal/fit
logic, and then restores the previous cached width:

```swift
if restorePreviousWidthAfterFit {
    column.cachedWidth = targetWidth
    defer { column.cachedWidth = previousWidth }
    revealTargetWidth()
}
```

(`NiriLayoutEngine+Sizing.swift:278-318`.)

However, viewport snap and visibility calculations use
`NiriContainer.effectiveViewportWidth`:

```swift
var effectiveViewportWidth: CGFloat {
    loneWindowLayoutWidthOverride ?? cachedWidth
}
```

(`Sources/Nehir/Core/Layout/Niri/NiriNode.swift:606-608`.)

At this moment `loneWindowLayoutWidthOverride` is still 1632, so it masks the
temporary 1926.3 `cachedWidth`. The reveal operation computes snaps from the old
width and sees the current `-204` offset as the center of the old geometry. It has
no reason to update the viewport target.

### 3. The override is cleared only after the early fit opportunity

The override is cleared later, when single-window geometry is prepared or rendered
for a manually sized column:

```swift
if context.container.hasManualSingleWindowWidthOverride {
    context.container.clearLoneWindowLayoutWidthOverride()
}
```

(`Sources/Nehir/Core/Layout/Niri/NiriLayout.swift:817-837,875-901`.)

By then `ensureSelectionVisibleForPendingWidth` has already completed with the
stale effective width.

### 4. Relayout's width-change gate compares two forms of the same current width

`NiriLayoutHandler.resolveSelection` attempts to recenter a lone window when its
resolved width changes. It captures `container.cachedWidth`, prepares geometry,
and compares the resulting geometry width with that captured value:

```swift
let previousSingleWindowWidth = ...container.cachedWidth ?? 0
let geometry = pass.engine.prepareSingleWindowViewport(...)
let widthChanged = abs((geometry.map { $0.rect.width } ?? 0)
    - previousSingleWindowWidth) > 1
```

Only `widthChanged`, initial setup, or removal calls
`resetViewportForCenteredLoneWindow`
(`Sources/Nehir/Core/Controller/NiriLayoutHandler.swift:795-820`).

For a manual lone-window width, `singleWindowViewportGeometry` resolves width from
that same `container.cachedWidth`
(`Sources/Nehir/Core/Layout/Niri/NiriLayout.swift:707-720,745-763`). During the
animation, the captured value and geometry value represent the same current
animation width and advance together. Their difference stays within the one-pixel
gate, so relayout does not recognize that an explicit command changed the desired
center.

### 5. Rendering faithfully applies the stale viewport offset

`SingleWindowViewportGeometry.renderedRect` offsets the canonical rect by the raw
viewport value:

```swift
rect.offsetBy(
    dx: workspaceOffset - effectiveViewOffset(viewOffset) + renderOffset.x,
    dy: renderOffset.y
)
```

(`NiriLayout.swift:48-75`.)

This is correct in isolation: the viewport offset is intentionally the authority
so gestures and side-snaps work. The defect is that the explicit width command
never updates that authority from `-204` to approximately `-56.85`.

## Five-why analysis

### Why 1: Why did the widened lone window remain uncentered?

Because its width grew toward 1926 pixels while Nehir kept requesting `x=212` and
left the viewport offset at `-204`.

### Why 2: Why did the viewport offset remain `-204`?

The pending-width reveal/recenter pass concluded that the current offset was
already correct and scheduled no viewport mutation.

### Why 3: Why did that pass still see the old centered geometry?

It temporarily changed `cachedWidth` to the target width, but
`effectiveViewportWidth` preferred the still-installed 1632-pixel
`loneWindowLayoutWidthOverride`.

### Why 4: Why did the later relayout not repair the center after clearing the override?

Its width-change detector compared prepared geometry against the current
`cachedWidth`; both values tracked the same animation width, so the explicit
change was invisible to the detector.

### Why 5: Why can an explicit width command lose its centering intent?

The lone-window implementation stores width in two authorities—policy override and
manual cached width—while viewport recentering is inferred indirectly from a
relayout width delta. The command changes authorities in an order that hides the
new width from the early fit and hides the transition from the later delta check.
There is no explicit transaction carrying the old viewport anchor and requested
new width through the policy-to-manual transition.

## Root cause

**Cycling a centered lone window to a manual width runs viewport fitting while the
old `loneWindowLayoutWidthOverride` still masks the target width, then clears that
override after relayout's width-change detector can no longer distinguish the
explicit width transition. The viewport therefore retains the center offset for
the old width.**

The stale offset pins the expanding frame to its previous x-position. Native frame
application then clamps the right edge at the display boundary, producing the
observed 1844-pixel width and repeated verification mismatches.

## Confidence boundaries

### Confirmed

1. The 1632-pixel lone window is correctly centered at `x=212` with offset `-204`.
2. The width command changes the target to 1926.3 pixels.
3. `currentOffset`, `targetOffset`, and Nehir's requested x-position remain
   unchanged throughout the width animation.
4. The correct centered x-position for the final width is approximately 65.
5. `applyColumnWidth` leaves the old lone-window override installed while pending
   width fitting runs.
6. `effectiveViewportWidth` prefers that override over the temporarily changed
   `cachedWidth`.
7. The later override-clearing path does not trigger the relayout width-change gate
   because geometry is compared with the same current cached width it resolves
   from.
8. The final observed width of 1844 ends exactly at display x=2056 when positioned
   at x=212.

### Not proven

1. Which native layer performs the final right-edge clamp: Helium, AppKit, or the
   AX/window-server frame application path. The exact layer is not needed to
   establish the Nehir-side centering root cause.

## Compatibility constraints for a future plan

1. Preserve deliberate lone-window side snaps and gesture offsets. A generic
   "always center on every relayout" rule would regress intentional parking.
2. Treat an explicit width command as distinct evidence from an unrelated relayout.
   If the lone window was centered when the command began, its center anchor should
   track the changing width; if it was deliberately side-snapped, the chosen anchor
   policy must be defined rather than inferred accidentally.
3. Keep policy-sized lone windows and manual width presets distinct; do not remove
   `hasManualSingleWindowWidthOverride` merely to force recentering.
4. Fix viewport authority before changing AX retry behavior. Retrying the same
   offscreen x-position cannot produce the intended centered frame.
5. Account for animated and reduced-motion width changes. The correction must not
   depend on observing a large per-frame cached-width delta.

## Relationship to the multi-column recenter defect (#170)

[`20260727-column-width-cycle-recenters-viewport-multi-column.md`](20260727-column-width-cycle-recenters-viewport-multi-column.md)
documents the inverse failure in the same command pipeline: in a multi-column
layout, `applyColumnWidth`'s explicit-navigation reveal force-recenters the
resized column on every cycle, destroying the user's viewport anchor (including
deliberate edge snaps). The two defects define one anchor policy with two
layout classes:

- **lone window (centered policy):** the anchor *is* the center and must track
  the changing width — this discovery shows it currently fails to;
- **multi-column managed layout:** the anchor is the user's current viewport
  position and must be preserved to the maximum extent the new geometry allows
  — the #170 discovery shows it is currently discarded in favor of center.

A shared fix shape falls out: classify the pre-resize anchor (center, left
edge, right edge, unsnapped), then derive the post-resize viewport target from
that anchor and the requested width, instead of letting reveal heuristics or
relayout width-delta detection rediscover intent.

## Investigation and fix boundary

The narrow source boundary is the transition in
`NiriLayoutEngine+Sizing.applyColumnWidth` from policy-controlled lone-window width
to manual width, together with `NiriLayoutHandler.resolveSelection`'s indirect
width-change recenter gate.

A future plan should evaluate an explicit anchor-preserving width transaction:

- capture whether the lone window is centered, left-snapped, or right-snapped
  before changing width authority;
- clear or bypass the stale `loneWindowLayoutWidthOverride` before calculating
  target-width snaps;
- derive the new viewport target from the requested width and captured anchor;
- carry that target through the width animation instead of asking each relayout to
  rediscover the command from `cachedWidth` deltas.

The expected centered result for this reproduction is stable and numeric:
`targetOffset≈-56.85`, `x≈65`, `width≈1926`, with no right-edge clamp or repeated
AX verification mismatch.
