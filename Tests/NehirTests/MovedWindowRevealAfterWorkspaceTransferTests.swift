// SPDX-FileCopyrightText: 2026 Aleksei Gurianov and Nehir contributors
// SPDX-FileComment: Provenance=nehir-original; See=NOTICE.md
//
// SPDX-License-Identifier: GPL-2.0-only

import AppKit
@testable import Nehir
import Testing

/// Moving a window to another workspace must leave its column inside the
/// destination viewport, not parked outside it.
///
/// `ensureSelectionVisible` does two things in sequence: it rebases
/// `viewOffsetPixels` so that retargeting `activeColumnIndex` does not shift what
/// is on screen, and it then calls `scrollToReveal` to bring the newly selected
/// column into view. The rebase is deliberately view-neutral, so the reveal is
/// the only step that can actually move the viewport.
///
/// The state under test is the one observed in a real reproduction: a window moved
/// into a four-column destination workspace ends up selected in the last column
/// while the viewport still rests at the far left, so the focused window is parked
/// offscreen and never receives a frame write.
@Suite struct MovedWindowRevealAfterWorkspaceTransferTests {
    /// The rebase preserves the on-screen view exactly, which is what makes the
    /// follow-up reveal load-bearing. Retargeting from column 2 to column 3 turns
    /// `viewOffsetPixels` -2360 into -3530 while `viewStart` stays at -20.
    @Test func rebasingActiveColumnPreservesViewStart() {
        let fixture = makeFixture()

        let beforeViewStart = fixture.state.viewPosPixels(columns: fixture.columns, gap: fixture.gap)
        #expect(beforeViewStart == -20)

        var state = fixture.state
        let oldActivePos = state.containerPosition(
            at: state.activeColumnIndex,
            containers: fixture.columns,
            gap: fixture.gap,
            sizeKeyPath: \.cachedWidth
        )
        let newActivePos = state.containerPosition(
            at: movedColumn,
            containers: fixture.columns,
            gap: fixture.gap,
            sizeKeyPath: \.cachedWidth
        )
        state.viewOffsetPixels.offset(delta: Double(oldActivePos - newActivePos))
        state.activeColumnIndex = movedColumn

        #expect(state.viewOffsetPixels.current() == -3530)
        #expect(state.viewPosPixels(columns: fixture.columns, gap: fixture.gap) == -20)
    }

    /// With the viewport resting at -20 and the moved window's column starting at
    /// 3510, the column is entirely outside the viewport.
    @Test func movedColumnIsParkedBeforeReveal() {
        let fixture = rebasedFixture()

        #expect(fixture.visibility(of: movedColumn) == .parked(.maximum))
    }

    /// The behaviour the real reproduction contradicts: a parked destination column
    /// must be revealed, leaving the moved window inside the viewport.
    @Test func revealsMovedColumnParkedOutsideDestinationViewport() {
        var fixture = rebasedFixture()
        #expect(fixture.visibility(of: movedColumn) == .parked(.maximum))

        let revealed = fixture.reveal(movedColumn, trigger: .automatic)

        #expect(revealed)
        #expect(fixture.visibility(of: movedColumn) != .parked(.maximum))
    }

    /// A scroll must actually be scheduled. In the reproduction the committed state
    /// had `currentViewStart == targetViewStart == -20`, meaning nothing was queued.
    @Test func schedulesScrollTowardMovedColumn() {
        var fixture = rebasedFixture()
        let originalTarget = fixture.state.viewOffsetPixels.target()

        _ = fixture.reveal(movedColumn, trigger: .automatic)

        #expect(fixture.state.viewOffsetPixels.target() != originalTarget)
    }

    /// Scroll lock does not exempt this: its own contract is that a fully parked
    /// target is still revealed, because focus otherwise lands somewhere invisible.
    @Test func revealsMovedColumnEvenWhenViewportIsScrollLocked() {
        var fixture = rebasedFixture()
        fixture.state.isScrollLocked = true
        #expect(fixture.visibility(of: movedColumn) == .parked(.maximum))

        let revealed = fixture.reveal(movedColumn, trigger: .automatic)

        #expect(revealed)
        #expect(fixture.visibility(of: movedColumn) != .parked(.maximum))
    }

    /// With motion disabled the reveal is instantaneous: `animateToOffset` takes its
    /// static fallback, so both the current and target offsets land on the snap and
    /// nothing is left animating. The five tests above exercise this path.
    @Test func revealWithMotionDisabledLandsStaticallyOnTheSnap() {
        var fixture = rebasedFixture()

        _ = fixture.reveal(movedColumn, trigger: .automatic, motion: .disabled)

        #expect(!fixture.state.viewOffsetPixels.isAnimating)
        #expect(fixture.state.viewOffsetPixels.current() == fixture.state.viewOffsetPixels.target())
    }

    /// `MotionPolicy.snapshot()` returns `.enabled`, so this is the configuration the
    /// runtime move path actually uses. Here `animateToOffset` installs a spring:
    /// the target moves to the snap while the current offset stays put for the
    /// display-link driver to interpolate.
    @Test func revealWithMotionEnabledSchedulesAnimationWithoutMovingCurrentOffset() {
        var fixture = rebasedFixture()
        let currentBefore = fixture.state.viewOffsetPixels.current()
        let targetBefore = fixture.state.viewOffsetPixels.target()

        _ = fixture.reveal(movedColumn, trigger: .automatic, motion: .enabled)

        #expect(fixture.state.viewOffsetPixels.isAnimating)
        #expect(fixture.state.viewOffsetPixels.target() != targetBefore)
        #expect(abs(fixture.state.viewOffsetPixels.current() - currentBefore) <= 1)
    }

    /// The plan-build step in `NiriLayoutHandler` decides whether the viewport moved
    /// — and so whether to emit a `.startNiriScroll` directive that drives the
    /// animation — by comparing offsets against their pre-reveal values. An animated
    /// reveal moves only the target, so a current-offset comparison alone does not
    /// observe it. Both deltas must be considered, or nothing drives the spring and
    /// the viewport never reaches the revealed column.
    @Test func animatedRevealIsObservableFromTheOffsetDeltas() {
        var fixture = rebasedFixture()
        let currentBefore = fixture.state.viewOffsetPixels.current()
        let targetBefore = fixture.state.viewOffsetPixels.target()

        _ = fixture.reveal(movedColumn, trigger: .automatic, motion: .enabled)

        let currentDelta = abs(fixture.state.viewOffsetPixels.current() - currentBefore)
        let targetDelta = abs(fixture.state.viewOffsetPixels.target() - targetBefore)

        // The current offset alone is not enough: it has not moved yet.
        #expect(currentDelta <= 1)
        // The target delta is what makes the scheduled scroll observable.
        #expect(targetDelta > 1)
        #expect(max(currentDelta, targetDelta) > 1)
    }

    /// The same combined check must also observe a static reveal, so the gate keeps
    /// working when animations are disabled.
    @Test func staticRevealIsObservableFromTheOffsetDeltas() {
        var fixture = rebasedFixture()
        let currentBefore = fixture.state.viewOffsetPixels.current()
        let targetBefore = fixture.state.viewOffsetPixels.target()

        _ = fixture.reveal(movedColumn, trigger: .automatic, motion: .disabled)

        let currentDelta = abs(fixture.state.viewOffsetPixels.current() - currentBefore)
        let targetDelta = abs(fixture.state.viewOffsetPixels.target() - targetBefore)

        #expect(max(currentDelta, targetDelta) > 1)
    }

    // MARK: - Fixture

    /// Four 1150pt columns with a 20pt gap at x = 0, 1170, 2340, 3510, seen through a
    /// 2560pt viewport — the destination workspace geometry from the reproduction.
    /// The moved window lands in the last column.
    private let movedColumn = 3

    private struct Fixture {
        let engine: NiriLayoutEngine
        let columns: [NiriContainer]
        let gap: CGFloat
        let viewportWidth: CGFloat
        var state: ViewportState

        var context: ViewportSnapContext {
            state.snapContext(columns: columns, gap: gap, viewportWidth: viewportWidth)
        }

        func visibility(of columnIndex: Int) -> ColumnVisibility {
            let context = context
            return context.visibility(
                of: columnIndex,
                viewportOffset: context.currentViewStart(in: state),
                in: state
            )
        }

        mutating func reveal(
            _ columnIndex: Int,
            trigger: RevealTrigger,
            motion: MotionSnapshot = .disabled
        ) -> Bool {
            engine.scrollToReveal(
                columnIndex: columnIndex,
                isFFM: false,
                state: &state,
                context: context,
                motion: motion,
                trigger: trigger
            )
        }
    }

    /// The pre-transfer destination state: selection on column 2, viewport at -20.
    private func makeFixture() -> Fixture {
        let engine = NiriLayoutEngine()
        engine.revealStyle = .auto
        engine.animationClock = AnimationClock()
        let workspaceId = UUID()

        var previous: NiriNode?
        for pid in pid_t(801) ... pid_t(804) {
            previous = engine.addWindow(
                handle: makeTestHandle(pid: pid),
                to: workspaceId,
                afterSelection: previous?.id
            )
        }

        let columns = engine.columns(in: workspaceId)
        for column in columns {
            column.width = .fixed(1150)
            column.cachedWidth = 1150
        }

        var state = ViewportState()
        state.animationClock = engine.animationClock
        state.activeColumnIndex = 2
        state.viewOffsetPixels = .static(-2360)

        return Fixture(
            engine: engine,
            columns: columns,
            gap: 20,
            viewportWidth: 2560,
            state: state
        )
    }

    /// `makeFixture()` after the view-neutral rebase onto the moved window's column:
    /// `activeColumnIndex` 3 with `viewOffsetPixels` -3530, i.e. `viewStart` -20.
    private func rebasedFixture() -> Fixture {
        var fixture = makeFixture()
        fixture.state.activeColumnIndex = movedColumn
        fixture.state.viewOffsetPixels = .static(-3530)
        return fixture
    }
}
