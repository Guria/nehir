# Nehir-managed fullscreen is never cleared except by re-toggling — Discovery

Scope: `toggleFullscreen` sets a persistent per-window `sizingMode`, and nothing
clears it when focus or selection moves to another window. Reported upstream in
this repository as issue #69.

Recorded as a follow-up from the investigation in
`completed/20260819-moved-window-parked-offscreen-on-workspace-transfer.md`,
where this was candidate 1 and was eliminated as a cause of *that* bug. It is a
real separate defect and has not been fixed.

All file/line references were verified against `main` at `f097f35a`
("Invalidate cached column spans when the monitor set changes (#198)").
**Re-verify before implementing; line numbers drift.**

---

## TL;DR

- **`sizingMode == .fullscreen` has exactly one exit: pressing `toggleFullscreen`
  again on that window.** No focus change, selection change, workspace transfer,
  or refresh clears it.
- **Verdict:** 🔴 **Open by inspection.** Matches the symptoms in issue #69
  ("Fullscreen window will not restore when switching focus to neighbours"),
  though the intermittent second half of that report — `toggleFullscreen`
  sometimes stopping working entirely — is not explained by this alone.
- Also worth deciding: whether a Nehir-fullscreen column should report its
  fullscreen width to the viewport model, which it currently does not.

## The sticky mode

`toggleFullscreen`
(`Sources/Nehir/Core/Layout/Niri/NiriLayoutEngine+Sizing.swift:443-450`) flips a
persistent property:

```swift
let newMode: SizingMode = window.sizingMode == .fullscreen ? .normal : .fullscreen
setWindowSizingMode(window, motion: motion, mode: newMode, state: &state)
```

A repository-wide search for assignments of `.normal` to `sizingMode` finds
exactly two sites —
`Sources/Nehir/Core/Layout/Niri/NiriLayoutEngine+Sizing.swift:937-939` and
`:999-1001` — and **both are guarded by `if window.sizingMode == .maximized`**,
so neither can clear `.fullscreen`. There is no un-fullscreen on selection
change, on incoming window transfer, or in the refresh pipeline.

The refresh path additionally privileges the fullscreen window: frame changes for
a node with `sizingMode == .fullscreen` are written with `forceApply: true`
(`Sources/Nehir/Core/Controller/NiriLayoutHandler.swift:1225-1234`), so its
full-working-frame geometry is pushed through even where an ordinary window's
frame write would be skipped.

## The viewport-width inconsistency

Separately from the sticky mode, the scroll model and the render model disagree
about how wide a fullscreen column is.

`effectiveViewportWidth`
(`Sources/Nehir/Core/Layout/Niri/NiriNode.swift:606-608`) is
`loneWindowLayoutWidthOverride ?? cachedWidth` — **no `sizingMode` term**. So a
Nehir-fullscreen column reports its ordinary narrow column width to everything
that reasons about scroll position and column visibility
(`ViewportState+Geometry.swift:329`, `:740-741`).

At render time, however,
`Sources/Nehir/Core/Layout/Niri/NiriLayout.swift:1025-1033` and `:1068-1071`
take `case .fullscreen, .maximized: frame = fullscreenRect`, where
`fullscreenRect = workingFrame` (`NiriLayout.swift:179-182`) — the whole working
area, regardless of the column's scroll position or width.

Consequence: in a strip that fits the viewport, a fullscreen column is neither
scrolled off nor marked hidden (so never parked or ordered below), yet is drawn
over the entire screen. A sibling window can therefore be focused and correctly
framed while being covered.

**Label:** this is a source-level reading, not a confirmed runtime observation.
The decisive runtime datum would be the frame writes for a workspace holding a
fullscreen window plus one other: if both the fullscreen window's
full-working-frame write and the sibling's narrow-column write appear, the
overlap is confirmed at the write layer.

## Not investigated

- The intermittent half of issue #69 — `toggleFullscreen` sometimes ceasing to
  un-fullscreen a window at all. The sticky mode above explains "focus change
  does not restore it", but not a toggle that stops responding. The reporter's
  workaround (toggle the window to floating and back) suggests state that the
  floating round-trip resets.
- Whether the intended behaviour is niri's: in niri, fullscreen is per-window and
  persists, and moving focus away does *not* exit it. If Nehir intends to match
  niri, issue #69 is partly a documentation matter and the real defect is the
  viewport-width inconsistency rather than the sticky mode. **This needs a
  product decision before an implementation plan.**

## Status

- Sticky `sizingMode`: **confirmed by inspection**, source cited above.
- Viewport-width inconsistency: **observed in source**; runtime effect
  **unconfirmed**.
- Relationship to issue #69: **consistent with the reported symptoms**, not
  verified against a reproduction.
- Blocked on: a decision about intended fullscreen semantics (niri-style
  persistent vs. exit-on-focus-change) before this can become a plan.
