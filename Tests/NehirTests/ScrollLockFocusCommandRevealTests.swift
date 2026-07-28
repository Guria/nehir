// SPDX-FileCopyrightText: 2026 Aleksei Gurianov and Nehir contributors
// SPDX-FileComment: Provenance=nehir-original; See=NOTICE.md
//
// SPDX-License-Identifier: GPL-2.0-only

import AppKit
@testable import Nehir
import NehirIPC
import Testing

/// End-to-end reveal behaviour of a focus command on a scroll-locked workspace, covered
/// at both entry points: the directional hotkey through `focusTarget`, and the IPC
/// window-focus command.
///
/// The reported repro: with scroll lock on, focusing a window whose column sat entirely
/// outside the viewport left the viewport pinned, so the window took focus while staying
/// invisible.
///
/// This suite goes through `focusTarget`, so the pure-layout bridge's own
/// `ensureSelectionVisible` call is on the path.
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

/// The same policy reached through the IPC window-focus command rather than a
/// directional focus hotkey, which is the path a workspace-bar click and `nehirctl`
/// both take.
@Suite @MainActor struct ScrollLockIPCWindowFocusRevealTests {
    /// Window 9113 lands in column 1, which is clipped at this geometry (800pt working
    /// frame, three 400pt columns at x = 0, 416, 832). Scroll lock leaves a target the
    /// user can already partly see alone, so focus moves but the viewport does not.
    @Test func windowFocusLeavesClippedTargetAloneWhileScrollLocked() throws {
        let monitor = makeLayoutPlanTestMonitor(width: 800, height: 600)
        let controller = makeLayoutPlanTestController(monitors: [monitor])
        let workspaceId = try #require(controller.workspaceManager.workspaceId(for: "1", createIfMissing: false))
        let handles = prepareIPCNiriState(
            on: controller,
            assignments: [
                (workspaceId, 9111),
                (workspaceId, 9112),
                (workspaceId, 9113)
            ],
            focusedWindowId: 9111
        )
        let engine = try #require(controller.niriEngine)
        engine.revealStyle = .center
        for column in engine.columns(in: workspaceId) {
            column.width = .fixed(400)
            column.cachedWidth = 400
        }
        let targetHandle = try #require(handles[9113])
        let targetNode = try #require(engine.findNode(for: targetHandle))
        var state = controller.workspaceManager.niriViewportState(for: workspaceId)
        state.selectedNodeId = engine.findNode(for: try #require(handles[9111]))?.id
        state.activeColumnIndex = 0
        state.viewOffsetPixels = .static(0)
        state.isScrollLocked = true
        controller.workspaceManager.updateNiriViewportState(state, for: workspaceId)
        let router = makeIPCCommandRouter(for: controller)

        let result = router.handle(
            IPCWindowRequest(
                name: .focus,
                windowId: IPCWindowOpaqueID.encode(
                    pid: targetHandle.id.pid,
                    windowId: targetHandle.id.windowId,
                    sessionToken: ipcCommandRouterSessionToken
                )
            )
        )

        let updated = controller.workspaceManager.niriViewportState(for: workspaceId)
        let context = engine.makeViewportSnapContext(
            columns: engine.columns(in: workspaceId),
            state: updated,
            workingFrame: controller.insetWorkingFrame(for: monitor),
            gaps: controller.gapSize(for: monitor)
        )
        let viewStart = context.currentViewStart(in: updated)
        #expect(result == .executed)
        #expect(updated.isScrollLocked)
        #expect(updated.selectedNodeId == targetNode.id)
        #expect(context.visibility(of: 1, viewportOffset: viewStart, in: updated) == .clipped(.maximum))
        #expect(viewStart == 0)
    }

    /// Window 9112 lands in column 2, which is parked past the right edge at this
    /// geometry. A parked target is revealed even while locked, or the window would take
    /// focus while staying invisible.
    @Test func windowFocusRevealsParkedTargetWhileScrollLocked() throws {
        let monitor = makeLayoutPlanTestMonitor(width: 800, height: 600)
        let controller = makeLayoutPlanTestController(monitors: [monitor])
        let workspaceId = try #require(controller.workspaceManager.workspaceId(for: "1", createIfMissing: false))
        let handles = prepareIPCNiriState(
            on: controller,
            assignments: [
                (workspaceId, 9111),
                (workspaceId, 9112),
                (workspaceId, 9113)
            ],
            focusedWindowId: 9111
        )
        let engine = try #require(controller.niriEngine)
        engine.revealStyle = .center
        for column in engine.columns(in: workspaceId) {
            column.width = .fixed(400)
            column.cachedWidth = 400
        }
        let targetHandle = try #require(handles[9112])
        let targetNode = try #require(engine.findNode(for: targetHandle))
        var state = controller.workspaceManager.niriViewportState(for: workspaceId)
        state.selectedNodeId = engine.findNode(for: try #require(handles[9111]))?.id
        state.activeColumnIndex = 0
        state.viewOffsetPixels = .static(0)
        state.isScrollLocked = true
        controller.workspaceManager.updateNiriViewportState(state, for: workspaceId)
        let router = makeIPCCommandRouter(for: controller)

        let result = router.handle(
            IPCWindowRequest(
                name: .focus,
                windowId: IPCWindowOpaqueID.encode(
                    pid: targetHandle.id.pid,
                    windowId: targetHandle.id.windowId,
                    sessionToken: ipcCommandRouterSessionToken
                )
            )
        )

        let updated = controller.workspaceManager.niriViewportState(for: workspaceId)
        let context = engine.makeViewportSnapContext(
            columns: engine.columns(in: workspaceId),
            state: updated,
            workingFrame: controller.insetWorkingFrame(for: monitor),
            gaps: controller.gapSize(for: monitor)
        )
        let viewStart = context.currentViewStart(in: updated)
        #expect(result == .executed)
        #expect(updated.isScrollLocked)
        #expect(updated.selectedNodeId == targetNode.id)
        #expect(context.visibility(of: 2, viewportOffset: viewStart, in: updated) == .fullyVisible)
    }
}
