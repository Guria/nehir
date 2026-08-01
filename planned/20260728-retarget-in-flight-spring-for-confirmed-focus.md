# Retarget an in-flight spring that would park newly confirmed focus — Plan

**Status:** planned. Scope is limited to the source-confirmed `.springInFlight` failure captured in [`../discovery/20260728-preserve-active-viewport-can-strand-confirmed-focus-offscreen.md`](../discovery/20260728-preserve-active-viewport-can-strand-confirmed-focus-offscreen.md). `.gesture`, `.alreadyConfirmedFocusedWindowChanged`, and `.closeRecoveryPin` are explicit do-not-touch boundaries.

## Overview

`AXEventHandler.handleManagedAppActivation` confirms managed focus before choosing a `PreserveActiveViewportReason`. Every reason except `.none` then bypasses `scrollToReveal` completely.

That is valid when an in-flight spring is already carrying the viewport toward the newly confirmed target. It fails when the spring destination is elsewhere: the focus token is accepted, `.springInFlight` skips the only reveal opportunity, and the spring can settle with the confirmed window fully parked outside the viewport. There is no later AX event or post-settle reconciliation that guarantees repair.

The repair must split `.springInFlight` by the newly confirmed column's visibility at the spring's **destination viewport**:

- preserve the current spring when its destination already contains at least part of the target column;
- allow the existing focus-reveal path to retarget the spring when its destination would leave that column fully parked;
- preserve the remaining reason priority when another lower-priority preservation policy also applies.

## Root cause

The current Boolean conflates two different questions:

1. Is the current viewport operation allowed to be interrupted?
2. Will the accepted focus target be visible when that operation finishes?

The source already has the geometry needed for the second question:

- `ViewportSnapContext.currentViewStart(in:)` evaluates the viewport's target position;
- `ViewportSnapContext.visibility(of:viewportOffset:in:)` classifies the target column there;
- the existing non-preserved branch already builds that context and calls `scrollToReveal`.

The context is currently built only after `preserveActiveViewport` has already suppressed the reveal branch, so `.springInFlight` never checks whether the preserved destination is safe.

## Chosen solution: synchronously retarget only a doomed spring

Use the existing focus-reveal machinery instead of introducing a pending post-settle obligation.

While choosing `PreserveActiveViewportReason`:

1. Detect the existing genuine spring condition without changing its pixel tolerance.
2. Resolve the newly activated node's column and build a classification-only `ViewportSnapContext` from the same inputs used by the reveal branch.
3. Classify that column at `context.currentViewStart(in: state)`, which is the spring destination.
4. If the destination visibility is `.parked`, do not select `.springInFlight`; continue through the lower-priority reasons:
   - `.alreadyConfirmedFocusedWindowChanged`;
   - `.closeRecoveryPin`;
   - `.none`.
5. If the destination is `.fullyVisible` or `.clipped`, preserve `.springInFlight` and the existing trajectory.
6. If the column, monitor, viewport, or required column dimensions cannot be resolved to finite positive geometry, classify the destination as unknown and conservatively retain `.springInFlight`.

The destination classification is computed before `activateNode` and `rebaseViewportAnchor`, while the preservation reason is selected. It is valid only when the dimensions needed to locate both the active and target columns are already resolved. Under that precondition, `rebaseViewportAnchor` shifts `activeColumnIndex` and the spring's `from`/`target` by matched deltas, so the physical target view start is unchanged. Do **not** reuse the pre-rebase context for the eventual reveal: `ViewportSnapContext.snapPoints` are precomputed, while `rebaseViewportAnchor` may resolve zero cached dimensions. Build a fresh production context after activation/rebase before tracing the reveal candidate and calling `scrollToReveal`.

In the captured failure, the remaining priority resolves to `.none`. The existing reveal branch then calls `scrollToReveal`, whose existing `animateToOffset` mutation replaces the doomed spring target. No new async registry, completion callback, or focus-episode state is needed.

Only `.parked` overrides `.springInFlight`. A clipped target is not stranded off-screen, and broadening the override to `.clipped` would change existing `revealPartial` and spring-preservation behavior outside the confirmed failure.

## Files

### Modify

- `Sources/Nehir/Core/Controller/AXEventHandler.swift`
  - make destination visibility available before finalizing `preserveActiveViewportReason`;
  - apply the `.parked`-only `.springInFlight` override;
  - keep the pre-rebase classification context separate from the fresh post-rebase reveal context;
  - record the destination classification and override decision in the existing focus-confirm trace.
- `Tests/NehirTests/AXEventHandlerTests.swift`
  - add the failing parked-destination regression;
  - add destination-visible and unresolved-geometry control regressions;
  - add a compound parked-destination/already-confirmed priority regression;
  - retain all existing preservation and manual-scroll-away regressions.

### Read-only references

- `Sources/Nehir/Core/Layout/Niri/ViewportState+Geometry.swift`
- `Sources/Nehir/Core/Layout/Niri/NiriLayoutEngine+ViewportCommands.swift`
- `completed/20260701-focus-confirm-skips-reveal-while-prior-spring-settles.md`
- `completed/20260706-stable-viewport-on-window-close-recovery.md`
- `completed/20260713-same-app-close-successor-reveals-before-actionable-removal.md`

## Do-not-touch fences

- Do not add, remove, or rename `PreserveActiveViewportReason` cases. Express the split through destination classification plus the existing cases; use trace fields rather than a new enum case.
- Do not change `.gesture` behavior or add post-gesture reconciliation. Gesture completion remains separate follow-up work.
- Do not weaken `.alreadyConfirmedFocusedWindowChanged`. A completed focus episode must continue to respect a deliberate manual scroll away from the focused window.
- Do not change `.closeRecoveryPin`, `sameAppCloseRecoveryViewportPins`, or close-successor selection. Close recovery owns whether a successor should be confirmed, redirected, or kept local.
- Do not change the relative ordering of `wasAlreadyConfirmedFocus` sampling, `confirmManagedFocus`, preservation-reason selection, `activateNode`, and `rebaseViewportAnchor`.
- Do not change the `settleTolerance` / `isSpringInFlight` numeric predicate shipped by `ca7ac372`.
- Do not change `ViewportOffset.isAnimating` globally.
- Do not change `NiriLayoutHandler.rebaseViewportAnchor`, `WorkspaceManager.applySessionPatch`, or the unconditional follow-up relayout request.
- Do not change `scrollToReveal`, reveal-style policy, scroll-lock policy, or `revealPartial` semantics.
- Do not touch files owned by adjacent active worktrees, including virtual-display parking and internal-display new-window placement work.
- Do not add a general pending-focus-visibility abstraction; this plan is bounded to the synchronous destination test required by the captured `.springInFlight` failure.

## Implementation steps

### Step 1 — Add the parked-destination regression first

**Files:**

- Modify: `Tests/NehirTests/AXEventHandlerTests.swift`

- [ ] Add `@Test @MainActor func focusConfirmationRetargetsInFlightSpringThatWouldParkNewFocusOffscreen() async`.
- [ ] Build at least three tiled columns so column 0 can be fully parked relative to a spring destination near later columns.
- [ ] Seed a real unconverged `.spring` using `CACurrentMediaTime()`, matching the deterministic pattern in `focusConfirmationPreservesActiveViewportSpring`.
- [ ] Before activation, build the production-equivalent `ViewportSnapContext`, record its physical target view start, and assert the incoming column is `.parked` there; this proves the fixture matches Capture B rather than a merely clipped destination.
- [ ] Confirm focus on the column-0 entry through `handleManagedAppActivation(... source: .focusedWindowChanged)`.
- [ ] Assert the new token becomes both selected and `confirmedManagedFocusToken`.
- [ ] Build the production-equivalent `ViewportSnapContext` after activation and assert the confirmed column is not `.parked` at `context.currentViewStart(in: updatedState)`.
- [ ] Assert the post-activation physical target view start differs from the recorded pre-activation target by more than the device-pixel tolerance. Compare physical view starts, not raw offset targets: the existing anchor-preserving rebase changes the raw target even on unfixed code.
- [ ] Run the fast gate and confirm the final-visibility and physical-destination assertions fail before implementation.

### Step 2 — Add the safe-destination and unresolved-geometry controls

**Files:**

- Modify: `Tests/NehirTests/AXEventHandlerTests.swift`

- [ ] Add `@Test @MainActor func focusConfirmationPreservesInFlightSpringWhenDestinationContainsNewFocus() async`.
- [ ] Seed a genuine unconverged spring whose destination already leaves the newly focused column `.fullyVisible`.
- [ ] Confirm focus through the same production activation path.
- [ ] Assert the new token becomes selected and confirmed.
- [ ] Assert the spring remains animating and its physical destination is unchanged within the device-pixel tolerance after the anchor-preserving rebase.
- [ ] Classify the new column at the destination and assert `.fullyVisible`.
- [ ] Strengthen `focusConfirmationPreservesActiveViewportSpring` with an explicit `.clipped` destination assertion while retaining its existing trajectory and anchor-rebase bookkeeping assertions. This protects both non-parked enum cases rather than only the new fully-visible control.
- [ ] Add `@Test @MainActor func focusConfirmationPreservesInFlightSpringWhenDestinationGeometryIsUnresolved() async`.
- [ ] Seed zero cached widths immediately before activation plus a genuine fresh-focus spring whose raw target would be misclassified as `.parked` if zero widths were treated as usable geometry.
- [ ] Let the existing anchor rebase resolve those widths, then assert the spring remains animating and its physical destination equals the expected anchor-preserved destination computed from the now-resolved old active-column position. A false `.parked` override would retarget through reveal and fail this assertion.
- [ ] Assert the new token becomes selected and confirmed. If existing diagnostics are directly observable, also assert `springDestinationVisibility=unknown`, `springDestinationOverride=false`, and `preserveActiveViewportReason=spring_in_flight`; do not add a test-only production API.
- [ ] Run the fast gate before implementation.

### Step 3 — Add the lower-priority preservation regression

**Files:**

- Modify: `Tests/NehirTests/AXEventHandlerTests.swift`

- [ ] Add `@Test @MainActor func parkedSpringDestinationFallsThroughToAlreadyConfirmedPreservation() async`.
- [ ] Seed the incoming token as `confirmedManagedFocusToken` before activation, then place its column fully parked relative to a genuine unconverged spring destination.
- [ ] Drive `handleManagedAppActivation(... source: .focusedWindowChanged)` so `.alreadyConfirmedFocusedWindowChanged` is the applicable lower-priority reason after the parked spring override.
- [ ] Record the pre-activation physical target view start and assert it remains unchanged after activation; forcing `.none` would reveal and fail this assertion.
- [ ] Assert the token remains selected and confirmed, and the spring remains in flight.
- [ ] If the existing test harness exposes the focus-confirm trace without production changes, also assert `springDestinationOverride=true` and `preserveActiveViewportReason=already_confirmed_focused_window_changed`; do not add a test-only production API solely for this assertion.
- [ ] Run the fast gate before implementation. Together with Step 1, this distinguishes "override only the doomed fresh-focus case" from both "never override" and "force every parked spring to `.none`".

### Step 4 — Split `.springInFlight` by destination visibility

**Files:**

- Modify: `Sources/Nehir/Core/Controller/AXEventHandler.swift`

- [ ] Hoist or factor the node-column, monitor, gap, working-frame, and column-list inputs needed to classify destination visibility before `preserveActiveViewportReason` is finalized.
- [ ] Compute destination visibility only for a tentative `.springInFlight` decision; avoid adding geometry work to unrelated preservation paths.
- [ ] Treat the pre-rebase classification as usable only when the viewport span and every effective column width needed to locate the active and target columns are finite and positive. Otherwise record `unknown` and preserve `.springInFlight`; do not let zero cached dimensions become a false `.parked` override.
- [ ] When visibility is `.parked`, continue through the lower-priority `.alreadyConfirmedFocusedWindowChanged` and `.closeRecoveryPin` checks rather than forcing `.none`.
- [ ] Preserve `.springInFlight` for `.fullyVisible`, `.clipped`, or unresolved geometry.
- [ ] Keep the existing `PreserveActiveViewportReason` cases unchanged; do not encode safe/doomed destination state as a new enum case.
- [ ] After `activateNode` and `rebaseViewportAnchor`, build a fresh snap context in the existing reveal block before candidate tracing and `scrollToReveal`. Reuse stable resolved inputs where appropriate, but do not reuse the classification context because its precomputed `snapPoints` may predate dimension resolution performed by rebase.
- [ ] Add `springDestinationVisibility=<classification|unknown>` and `springDestinationOverride=<true|false>` to `ax_focus_confirm_before_activate` when a genuine spring was evaluated.
- [ ] Run the fast gate; all new and existing `AXEventHandlerTests` must pass before continuing.

### Step 5 — Verify policy boundaries

**Files:**

- Modify only if an assertion needs strengthening: `Tests/NehirTests/AXEventHandlerTests.swift`

- [ ] Run the strengthened `focusConfirmationPreservesActiveViewportSpring` regression and verify its destination remains explicitly `.clipped` while the physical spring trajectory is preserved.
- [ ] Run `reconfirmedFocusViaFocusedWindowChangedPreservesViewport` unchanged and verify deliberate manual scroll-away still does not snap back.
- [ ] Run `parkedSpringDestinationFallsThroughToAlreadyConfirmedPreservation` and verify the compound parked-spring/manual-scroll-away contract stays preserved.
- [ ] Verify no `.gesture` or `.closeRecoveryPin` branch changed in the diff.
- [ ] Run the fast gate again.

### Step 6 — Full validation

- [ ] Run formatting and inspect the diff for unrelated changes.
- [ ] Run the full project gate: `mise run check`.
- [ ] Confirm the implementation is limited to `AXEventHandler.swift` and `AXEventHandlerTests.swift` unless a justified source-backed deviation is recorded in the commit message.

## Test gates

### Fast gate after each step

```sh
swift test --no-parallel --filter AXEventHandlerTests
```

This intentionally uses the suite-level filter rather than relying on Swift Testing's exact rendered spelling for individual test names.

### Full final gate

```sh
mise run check
```

`mise run check` covers format checking, lint, build, and the repository's isolated full test sequence.

## Runtime validation

A validating capture must inline the evidence; do not cite machine-local trace filenames or filesystem paths.

### Parked-destination case

For one token, show:

```text
ax_focus_confirm_before_activate
  wasAlreadyConfirmedFocus=false
  springDestinationVisibility=parked(...)
  springDestinationOverride=true
  preserveActiveViewportReason=<remaining reason, normally none>
  currentViewStart=<moving value>
  targetViewStart=<doomed pre-retarget value>

ax_focus_confirm_reveal_candidate
  token=<same token>
  visibility=parked(...)

ax_focus_confirm_reveal_result
  token=<same token>
  didReveal=true

scroll_animation_stop
  selectedNode=<same token>
  confirmedFocus=<same token>
  hidden=<nil>
```

Acceptance requires proving final visibility, not merely proving that the viewport moved.

### Destination-visible control

Show:

```text
ax_focus_confirm_before_activate
  springDestinationVisibility=fullyVisible
  springDestinationOverride=false
  preserveActiveViewportReason=spring_in_flight

ax_focus_confirm_reveal_skipped
  skipReason=preserve_active_viewport

scroll_animation_stop
  selectedNode=<same token>
  confirmedFocus=<same token>
  hidden=<nil>
```

The spring's physical destination must remain the same as before focus confirmation.

## Acceptance criteria

- A newly confirmed token cannot remain fully parked solely because its only confirmation arrived during a spring whose destination excluded it.
- The existing spring is retargeted through the existing reveal path when the destination classifies the target as `.parked`.
- A spring whose destination already shows the target remains uninterrupted.
- Unresolved destination geometry preserves the spring conservatively instead of producing a false parked override.
- `.gesture`, `.alreadyConfirmedFocusedWindowChanged`, and `.closeRecoveryPin` retain their existing contracts.
- No new deferred-obligation state, animation-completion hook, or cross-module abstraction is introduced.
- Focused tests and `mise run check` pass.
- Runtime evidence proves both the repaired failure and the preserved control behavior.

## Required implementation commit

Use one focused implementation commit with this subject:

```text
Retarget in-flight spring when it would park confirmed focus
```

The body must state:

- destination visibility now distinguishes safe and doomed `.springInFlight` preservation;
- `.parked` falls through to the remaining preservation priority so the existing reveal path can retarget the spring;
- `.fullyVisible` and `.clipped` preserve the existing trajectory;
- `.gesture`, `.alreadyConfirmedFocusedWindowChanged`, and `.closeRecoveryPin` are unchanged;
- focused and full validation commands run and their results;
- any justified deviation from the two-file scope.

End the commit message with:

```text
Co-Authored-By: Claude <noreply@anthropic.com>
```
