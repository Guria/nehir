# Hide Empty Workspaces dropped the workspace you are standing on — shipped

**Status:** shipped on `main` as `64e0b98c` ("Keep the active workspace on the bar
when hiding empty ones") on 2026-07-28. One commit, no merge commit, branch
`patch/bar-hide-empty-keeps-focused-workspace`.

**Origin:** upstream port candidate `ac0a0287` from the sweep
[`../discovery/20260728-upstream-post-roadmap-candidates.md`](../discovery/20260728-upstream-post-roadmap-candidates.md)
(Lane 4, 🔴 XS, recommendation #2). Adapted from `BarutSRB/OmniWM` commit
`ac0a0287` ("Keep the active workspace on the bar when hiding empty ones"),
authored by `holmns`.

## The defect

With **Hide Empty Workspaces** enabled, navigating to a workspace that held no
bar-visible windows left the workspace bar with **no item reporting focus at
all** — the "you are here" highlight disappeared from every pill, and the
remaining pills reflowed to close the gap.

The cause was ordering, not logic. `localWorkspaceItems` ran the empty filter
`workspaces.filter(\.hasBarOccupancy)` *before* resolving
`activeWorkspaceId = workspaceManager.activeWorkspace(on: monitor.id)?.id`. By
the time `isFocused: snapshot.workspace.id == activeWorkspaceId` was evaluated
for each surviving item, the workspace the user was standing on had already been
filtered out, so no item could match.

The foreign-display pill path carried the same shape: an empty workspace on
another display was dropped unconditionally, including the workspace that
display was parked on.

## What shipped

All in `Sources/Nehir/UI/WorkspaceBar/WorkspaceBarDataSource.swift`:

- `:151` — `activeWorkspaceId` is resolved **before** the empty filter, not
  after it.
- `:153-157` — the filter became
  `filter { $0.hasBarOccupancy || $0.workspace.id == activeWorkspaceId }`. The
  active workspace survives as a bare label with no window icons, and keeps its
  highlight (`:193`).
- `:227` — the foreign path gained the matching carve-out, keyed on each other
  display's own active workspace:
  `if options.hideEmptyWorkspaces, projectedEntries.isEmpty, workspace.id != activeOnOther { continue }`.
  `activeOnOther` was already computed at `:219` for `isActiveOnHomeDisplay`
  (`:239`), so this reuses an existing value rather than adding a lookup.
- `:204-208` — the `foreignWorkspaceItems` doc comment now states the carve-out.

Upstream's split notch island is deliberately **not** ported; Nehir has no such
layout, and that half of `ac0a0287` was ignored.

## The foreign-pill decision, and why it was reversed

Upstream has no foreign-pill path, so this had no reference answer and was left
open in the sweep's recommendation #2 ("decide the same question for the
foreign-pill path").

It was first decided **against** extending the carve-out, on two grounds: a
foreign pill hardcodes `isFocused: false`, so hiding it costs no focus
indicator; and `Tests/NehirTests/WorkspaceBarDataSourceTests.swift` already
asserted that an empty foreign workspace is hidden "consistent with local
items".

That was **overruled by the user and reversed**, and the reversal is the shipped
behaviour. The reasoning that carried: `isActiveOnHomeDisplay` is a real
per-display "parked here" marker with its own rendering, and a display parked on
an empty workspace losing its pill entirely is the same class of defect one
level removed — the bar stops showing where that display is. The consistency
argument cuts the other way once the local path keeps its active workspace: the
consistent rule is "each display keeps the workspace it is on", not "empty means
hidden everywhere".

**Lesson for future sweeps.** The first decision leaned on an existing test as
evidence of a considered policy. It was not — the test recorded the state of the
world before the local carve-out existed, and the local change made its stated
rationale ("consistent with local items") false. An existing assertion is a
record of a past decision, not proof the decision still holds after the
behaviour around it changes.

## Tests

`Tests/NehirTests/WorkspaceBarDataSourceTests.swift`:

- `foreignEmptyWorkspacesRespectHideEmptyWorkspaces` (`:388`) was **retargeted**
  at a workspace the secondary display is *not* parked on, so it still covers
  the exclusion path.
- `foreignActiveWorkspaceSurvivesHideEmptyWorkspaces` (`:398`) covers the
  carve-out itself.
- Both need a new fixture, `makeForeignHideEmptyFixture` (`:427`), giving the
  secondary display **two** empty workspaces. The shared
  `makeTwoMonitorLayoutPlanTestController` fixture assigns the secondary display
  exactly one workspace and activates it, which is the single topology where the
  empty policy and the active carve-out cannot be told apart.

The carve-out test was falsified before acceptance: reverting only the `:227`
predicate fails `foreignActiveWorkspaceSurvivesHideEmptyWorkspaces` while the
retargeted exclusion test keeps passing, so neither is vacuous.

Note on process: `docs/TESTING.md` gates test edits on user-confirmed runtime
validation. These tests were written inside the implementation commit under an
explicit grant from the user, not by the default rule.

## Verification

`mise run check` (format + lint + build + test) green — 1484 tests across 129
suites. `mise run license:check` green.

Two unrelated pre-existing flakes were observed while gating and confirmed
against unmodified base source, not caused by this change: `IPCServerTests`
aborting with `unexpected signal code 5` under the full-suite runner while
passing standalone, and `WMControllerFocusTests`
`moveMouseToWindowConvertsAppKitCenterBeforeWarping` /
`moveMouseToFocusedWarpsToEmptyWorkspaceMonitorOnSwitch` failing with
`warpedPoints → []`. Both passed on re-run. Worth a separate discovery if they
recur.

## Provenance and release note

- `.provenance.json` records the borrow under `upstreamCommits` for
  `Sources/Nehir/UI/WorkspaceBar/WorkspaceBarDataSource.swift` → `ac0a0287`, per
  `NOTICE.md`'s audit-map requirement. SPDX headers are generated, not
  hand-edited.
- A `patch` changeset ships the user-facing note and credits `holmns` via
  `contributors: [holmns]`.

## Manual repro this closes

Enable **Hide Empty Workspaces**. On the primary display, move to a workspace
with no windows: its pill stays on the bar as a bare label, stays highlighted,
and the neighbouring pills do not reflow. With **Show workspaces from other
displays** also on, park a secondary display on an empty workspace: its compact
foreign pill stays on the primary bar with its `D2`-style monitor tag and no
window icons.
