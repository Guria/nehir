# Cancelled plan: remove lone/narrow-column viewport-bound snaps

**Status: cancelled as a no-op. Do not implement.**

This plan previously proposed changing
`Sources/Nehir/Core/Layout/Niri/ViewportState+Geometry.swift` so
`computeSnapGrid(...)` would append `viewportStartBounds` endpoints only when
the total strip width exceeded the viewport width. It also proposed regression
tests requiring every resting snap of a narrow strip to keep all columns fully
on-screen.

That desired behavior was based on an incorrect product assumption. The two
viewport-bound endpoints are intentional persistent desktop-reveal snaps. They
allow a user to fling the strip aside, release the trackpad, and continue
viewing the desktop while a small edge sliver remains available. This behavior
is useful and intended for a lone column and for a strip narrower than the
viewport; it does not depend on a neighboring column.

## Do not implement the former approach

The rejected condition was equivalent to:

```swift
let stripTotal = totalWidth(columns: columns, gap: gap)
if stripTotal > viewportWidth + pixelTolerance {
    points.append(SnapPoint(offset: bounds.lowerBound, columnIndex: 0, kind: .rightEdge))
    points.append(SnapPoint(offset: bounds.upperBound, columnIndex: columns.count - 1, kind: .leftEdge))
}
```

This would remove a user-visible feature, not fix a bug. The associated tests
would encode the same wrong invariant and must not be added.

## Correct durable invariant

- Keep both viewport bounds as resting snap targets regardless of whether the
  strip fills the viewport.
- Preserve the default 5%-sliver behavior of `viewportStartBounds`.
- Distinguish these persistent desktop-reveal snaps from per-column edge/center
  snaps used for normal window positioning.
- Tests should positively assert that a lone narrow column retains both bound
  snaps and that a projected fling can settle on one.

See `noop/20260707-lone-column-fling-snaps-to-offscreen-overscroll-bound.md` for
the corrected investigation, arithmetic, source confirmation, and distinction
from separate momentum/neighbor-selection questions.

No changeset or user-visible bug-fix commit is warranted for the rejected plan.
