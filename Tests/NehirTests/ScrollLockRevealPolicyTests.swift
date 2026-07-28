// SPDX-FileCopyrightText: 2026 Aleksei Gurianov and Nehir contributors
// SPDX-FileComment: Provenance=nehir-original; See=NOTICE.md
//
// SPDX-License-Identifier: GPL-2.0-only

import AppKit
@testable import Nehir
import Testing

/// Viewport scroll lock answers to target visibility, not to who asked for the reveal.
///
/// A target outside the viewport is revealed for every trigger, because focus landing
/// somewhere invisible means input disappears into a window the user cannot see. A
/// partially visible target is left alone for every trigger, however little of it shows.
@Suite struct ScrollLockRevealPolicyTests {
    // MARK: - Parked targets are revealed while locked

    @Test func revealsParkedTargetWhileLockedForAutomaticTrigger() {
        var fixture = makeFixture()
        fixture.state.isScrollLocked = true
        #expect(fixture.visibility(of: parkedColumn) == .parked(.maximum))

        let revealed = fixture.reveal(parkedColumn, trigger: .automatic)

        #expect(revealed)
        #expect(fixture.visibility(of: parkedColumn) == .fullyVisible)
    }

    @Test func revealsParkedTargetWhileLockedForExplicitNavigation() {
        var fixture = makeFixture()
        fixture.state.isScrollLocked = true
        #expect(fixture.visibility(of: parkedColumn) == .parked(.maximum))

        let revealed = fixture.reveal(parkedColumn, trigger: .explicitNavigation)

        #expect(revealed)
        #expect(fixture.visibility(of: parkedColumn) == .fullyVisible)
    }

    // MARK: - Partially visible targets are left alone while locked

    @Test func leavesClippedTargetAloneWhileLockedForAutomaticTrigger() {
        var fixture = makeFixture()
        fixture.state.isScrollLocked = true
        let originalTarget = fixture.state.viewOffsetPixels.target()
        #expect(fixture.visibility(of: clippedColumn) == .clipped(.maximum))

        let revealed = fixture.reveal(clippedColumn, trigger: .automatic)

        #expect(!revealed)
        #expect(fixture.state.viewOffsetPixels.target() == originalTarget)
    }

    /// The case the reveal policy changed: an explicit focus command no longer drags a
    /// column the user can already see over to a snap just because it is clipped.
    @Test func leavesClippedTargetAloneWhileLockedForExplicitNavigation() {
        var fixture = makeFixture()
        fixture.state.isScrollLocked = true
        let originalTarget = fixture.state.viewOffsetPixels.target()
        #expect(fixture.visibility(of: clippedColumn) == .clipped(.maximum))

        let revealed = fixture.reveal(clippedColumn, trigger: .explicitNavigation)

        #expect(!revealed)
        #expect(fixture.state.viewOffsetPixels.target() == originalTarget)
    }

    @Test func leavesFullyVisibleTargetAloneWhileLockedForExplicitNavigation() {
        var fixture = makeFixture()
        fixture.state.isScrollLocked = true
        let originalTarget = fixture.state.viewOffsetPixels.target()
        #expect(fixture.visibility(of: fullyVisibleColumn) == .fullyVisible)

        let revealed = fixture.reveal(fullyVisibleColumn, trigger: .explicitNavigation)

        #expect(!revealed)
        #expect(fixture.state.viewOffsetPixels.target() == originalTarget)
    }

    // MARK: - Unlocked behaviour is untouched

    @Test func revealsClippedTargetWhenUnlocked() {
        var fixture = makeFixture()
        #expect(fixture.visibility(of: clippedColumn) == .clipped(.maximum))

        let revealed = fixture.reveal(clippedColumn, trigger: .automatic)

        #expect(revealed)
        #expect(fixture.visibility(of: clippedColumn) == .fullyVisible)
    }

    @Test func neverRevealsForFocusFollowsMouseEvenWhenParkedAndUnlocked() {
        var fixture = makeFixture()
        let originalTarget = fixture.state.viewOffsetPixels.target()
        #expect(fixture.visibility(of: parkedColumn) == .parked(.maximum))

        let revealed = fixture.reveal(parkedColumn, isFFM: true, trigger: .automatic)

        #expect(!revealed)
        #expect(fixture.state.viewOffsetPixels.target() == originalTarget)
    }

    // MARK: - Fixture

    /// Three 400pt columns with an 8pt gap laid out at x = 0, 408, 816, seen through a
    /// 600pt viewport resting at 0. That makes column 0 fully visible, column 1 clipped
    /// with 192pt of 400 showing, and column 2 parked past the right edge.
    private let fullyVisibleColumn = 0
    private let clippedColumn = 1
    private let parkedColumn = 2

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
            isFFM: Bool = false,
            trigger: RevealTrigger
        ) -> Bool {
            engine.scrollToReveal(
                columnIndex: columnIndex,
                isFFM: isFFM,
                state: &state,
                context: context,
                motion: .disabled,
                trigger: trigger
            )
        }
    }

    private func makeFixture() -> Fixture {
        let engine = NiriLayoutEngine()
        engine.revealStyle = .auto
        engine.animationClock = AnimationClock()
        let workspaceId = UUID()

        var previous: NiriNode?
        for pid in pid_t(701) ... pid_t(703) {
            previous = engine.addWindow(
                handle: makeTestHandle(pid: pid),
                to: workspaceId,
                afterSelection: previous?.id
            )
        }

        let columns = engine.columns(in: workspaceId)
        for column in columns {
            column.width = .fixed(400)
            column.cachedWidth = 400
        }

        var state = ViewportState()
        state.animationClock = engine.animationClock
        state.activeColumnIndex = 0
        state.viewOffsetPixels = .static(0)

        return Fixture(
            engine: engine,
            columns: columns,
            gap: 8,
            viewportWidth: 600,
            state: state
        )
    }
}
