# No-op: lone/narrow-column fling settles at a persistent desktop-reveal bound

**Verdict: intentional behavior, not a defect. No production fix should be made.**

This item was originally classified as a viewport-geometry bug because a fast
horizontal trackpad fling can settle a lone column at a viewport bound where
only about 5% of the column remains visible. That classification was wrong.
The bound is an intentional **persistent desktop-reveal snap**: it allows the
user to release the trackpad and continue viewing the desktop. It applies even
when the workspace contains one column or the complete strip is narrower than
the viewport.

Verified against the main Nehir source tree on 2026-07-27.

## Intended UX invariant

There are two different families of snap points and they must not be conflated:

1. **Per-column edge and center snaps** place a column usefully within the
   viewport for window navigation.
2. **Viewport-bound snaps** park the strip at either extreme with only
   `edgeVisibleFraction` (5% by default) of the edge column visible. Their
   purpose is to expose the desktop persistently after the gesture ends.

The second family does **not** require a neighboring column and is not merely a
"peek the neighbor" behavior. For a lone or narrow strip, the empty area being
revealed is the desktop itself. Removing those snaps when `totalWidth <=
viewportWidth` would regress this feature.

## Observed behavior is consistent with the invariant

A representative workspace had one column with:

- column width `1480`;
- gap `6`;
- viewport width `2466`;
- default visible fraction `0.05`.

`viewportStartBounds` therefore produces:

```text
lower = 1480 * 0.05 + 6 - 2466 = -2386
upper = 1480 - 1480 * 0.05 - 6 = 1400
```

The snap grid contains the ordinary fully-visible positions (`-980`, `-493`,
`-6`) and the two persistent desktop-reveal bounds (`-2386`, `1400`). A fling
projected to `1147` selects the nearest point, `1400`, and the gesture-end
spring rests there. That leaves a small edge sliver available for returning to
the window while the desktop remains visible without continued touch input.

A later reproduction used one `1632`-wide column in a `2040`-wide viewport and
settled at `1544.4` or `-1952.4`, again exactly the 5%-sliver bounds. This is the
same intended feature, not evidence of an offscreen-window defect.

## Source confirmation

`Sources/Nehir/Core/Layout/Niri/ViewportState+Geometry.swift` owns the behavior:

- `viewportStartBounds(...)` calculates the two intentional persistent
  overscroll limits from `edgeVisibleFraction`.
- `computeSnapGrid(...)` unconditionally adds both limits as snap points.
  This is deliberate, including for one column or a strip narrower than the
  viewport.

`Sources/Nehir/Core/Layout/Niri/ViewportState+Gestures.swift` then selects the
snap nearest the projected fling position and creates the gesture-end spring.
The fact that the spring reaches and remains at a bound is therefore expected.

The comments and regression coverage in the main source tree should explicitly
name the persistent desktop-reveal purpose so future investigations do not infer
that the bounds only exist to reveal neighboring columns.

## Rejected change

Do **not** gate viewport-bound snap generation with:

```swift
if totalWidth(columns: columns, gap: gap) > viewportWidth + pixelTolerance {
    // append bounds
}
```

That condition removes the persistent desktop-reveal positions precisely when a
lone/narrow workspace has the most desktop available to expose. It changes an
intentional resting state into transient-only overscroll and is a regression.

The associated implementation plan has been moved to
`noop/20260707-lone-column-fling-snaps-offscreen-overscroll-bound-plan.md` and
marked cancelled.

## Related distinction

This no-op verdict does not automatically resolve every trackpad complaint.
`discovery/20260627-trackpad-fling-snap-overshoot-to-neighbor-column.md` concerns
momentum selecting another column's edge after a small flick. That is a separate
tuning question. The persistent lone-column desktop-reveal bound documented
here must be preserved while evaluating any momentum or nearest-snap changes.
