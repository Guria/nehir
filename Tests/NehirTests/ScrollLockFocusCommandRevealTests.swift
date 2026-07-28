// SPDX-FileCopyrightText: 2026 Aleksei Gurianov and Nehir contributors
// SPDX-FileComment: Provenance=nehir-original; See=NOTICE.md
//
// SPDX-License-Identifier: GPL-2.0-only

import AppKit
@testable import Nehir
import Testing

/// End-to-end reveal behaviour of a directional focus command on a scroll-locked
/// workspace, exercised through `focusTarget` so the pure-layout bridge's own
/// `ensureSelectionVisible` call is on the path.
///
/// The reported repro: with scroll lock on, focusing a window whose column sat entirely
/// outside the viewport left the viewport pinned, so the window took focus while staying
/// invisible.
@Suite struct ScrollLockFocusCommandRevealTests {
    @Test func focusCommandRevealsParkedColumnWhileLocked() {
        var fixture = makeFixture()
        fixture.state.isScrollLocked = true

        // Step onto the clipped middle column first, then onto the parked one.
        fixture.focusRight()
        fixture.focusRight()

        #expect(fixture.selectedColumnIndex == 2)
        #expect(fixture.visibility(of: 2) == .fullyVisible)
    }

    @Test func focusCommandLeavesClippedColumnAloneWhileLocked() {
        var fixture = makeFixture()
        fixture.state.isScrollLocked = true
        let originalViewStart = fixture.viewStart

        fixture.focusRight()

        #expect(fixture.selectedColumnIndex == 1)
        #expect(fixture.visibility(of: 1) == .clipped(.maximum))
        #expect(fixture.viewStart == originalViewStart)
    }

    @Test func focusCommandRevealsClippedColumnWhenUnlocked() {
        var fixture = makeFixture()

        fixture.focusRight()

        #expect(fixture.selectedColumnIndex == 1)
        #expect(fixture.visibility(of: 1) == .fullyVisible)
    }

    // MARK: - Fixture

    /// Three 400pt columns at x = 0, 408, 816 behind a 600pt working frame resting at 0:
    /// column 0 fully visible, column 1 clipped, column 2 parked past the right edge.
    private struct Fixture {
        let engine: NiriLayoutEngine
        let workspaceId: WorkspaceDescriptor.ID
        let workingFrame: CGRect
        let gap: CGFloat
        var state: ViewportState

        private var context: ViewportSnapContext {
            state.snapContext(
                columns: engine.columns(in: workspaceId),
                gap: gap,
                viewportWidth: workingFrame.width
            )
        }

        var viewStart: CGFloat {
            context.currentViewStart(in: state)
        }

        var selectedColumnIndex: Int? {
            guard let selectedNodeId = state.selectedNodeId,
                  let node = engine.findNode(by: selectedNodeId),
                  let column = engine.column(of: node)
            else {
                return nil
            }
            return engine.columnIndex(of: column, in: workspaceId)
        }

        func visibility(of columnIndex: Int) -> ColumnVisibility {
            let context = context
            return context.visibility(
                of: columnIndex,
                viewportOffset: context.currentViewStart(in: state),
                in: state
            )
        }

        mutating func focusRight() {
            guard let selectedNodeId = state.selectedNodeId,
                  let selected = engine.findNode(by: selectedNodeId)
            else {
                Issue.record("Fixture lost its selection")
                return
            }
            let target = engine.focusTarget(
                direction: .right,
                currentSelection: selected,
                in: workspaceId,
                motion: .disabled,
                state: &state,
                workingFrame: workingFrame,
                gaps: gap
            )
            if let target {
                state.selectedNodeId = target.id
            }
        }
    }

    private func makeFixture() -> Fixture {
        let engine = NiriLayoutEngine()
        engine.revealStyle = .auto
        engine.animationClock = AnimationClock()
        let workspaceId = UUID()
        let root = engine.ensureRoot(for: workspaceId)

        for windowId in 1 ... 3 {
            let column = NiriContainer()
            column.width = .fixed(400)
            column.cachedWidth = 400
            root.appendChild(column)

            let token = WindowToken(pid: 704, windowId: windowId)
            let window = NiriWindow(token: token)
            column.appendChild(window)
            engine.tokenToNode[token] = window
            column.setActiveTileIdx(0)
        }

        var state = ViewportState()
        state.animationClock = engine.animationClock
        state.activeColumnIndex = 0
        state.viewOffsetPixels = .static(0)
        state.selectedNodeId = engine.columns(in: workspaceId).first?.windowNodes.first?.id

        return Fixture(
            engine: engine,
            workspaceId: workspaceId,
            workingFrame: CGRect(x: 0, y: 0, width: 600, height: 800),
            gap: 8,
            state: state
        )
    }
}
