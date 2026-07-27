// SPDX-FileCopyrightText: 2026 Aleksei Gurianov and Nehir contributors
// SPDX-FileComment: Provenance=nehir-original; See=NOTICE.md
//
// SPDX-License-Identifier: GPL-2.0-only

import ApplicationServices
import CoreGraphics
import Foundation
@testable import Nehir
import Testing

/// Regression coverage for #170: changing a column's width must not move the
/// viewport while the resized column stays fully visible at the user's current
/// anchor (including deliberate edge snaps). When the new width does clip the
/// column, the viewport moves only the minimum distance that restores full
/// visibility, and an over-wide column anchors its leading edge.
@MainActor
struct ColumnWidthCycleViewportAnchorTests {
    private struct Fixture {
        let controller: WMController
        let workspaceId: WorkspaceDescriptor.ID
        let engine: NiriLayoutEngine
        let nodes: [NiriWindow]
        let gap: CGFloat
        let workingFrame: CGRect
    }

    private func makeFixture(widthFactors: [CGFloat]) async -> Fixture? {
        let controller = makeLayoutPlanTestController()
        guard let monitor = controller.workspaceManager.monitors.first,
              let workspaceId = controller.workspaceManager.activeWorkspaceOrFirst(on: monitor.id)?.id
        else {
            Issue.record("Missing monitor or workspace for width-cycle fixture")
            return nil
        }

        controller.enableNiriLayout(revealStyle: .auto)
        controller.updateNiriConfig(balancedColumnCount: 1)
        await controller.layoutRefreshController.waitForRefreshWorkForTests()
        controller.syncMonitorsToNiriEngine()
        guard let engine = controller.niriEngine else {
            Issue.record("Missing Niri engine for width-cycle fixture")
            return nil
        }

        let workingFrame = controller.insetWorkingFrame(for: monitor)
        let gap = controller.gapSize(for: monitor)

        let pid: pid_t = 7_800
        var nodes: [NiriWindow] = []
        var previousNodeId: NodeId?
        for index in widthFactors.indices {
            let windowId = 7_801 + index
            let token = controller.workspaceManager.addWindow(
                AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: windowId),
                pid: pid,
                windowId: windowId,
                to: workspaceId
            )
            let node = engine.addWindow(
                token: token,
                to: workspaceId,
                afterSelection: previousNodeId,
                focusedToken: token
            )
            nodes.append(node)
            previousNodeId = node.id
        }

        let columns = engine.columns(in: workspaceId)
        guard columns.count == widthFactors.count else {
            Issue.record("Expected \(widthFactors.count) columns, got \(columns.count)")
            return nil
        }
        for (column, factor) in zip(columns, widthFactors) {
            let width = (workingFrame.width * factor).rounded()
            column.width = .fixed(width)
            column.cachedWidth = width
            column.cachedHeight = workingFrame.height
        }

        return Fixture(
            controller: controller,
            workspaceId: workspaceId,
            engine: engine,
            nodes: nodes,
            gap: gap,
            workingFrame: workingFrame
        )
    }

    /// Places the viewport so its view start is exactly `viewStart` with
    /// `activeColumn` selected, returning the resolved start for preconditions.
    private func park(_ fx: Fixture, activeColumn: Int, viewStart: CGFloat) -> CGFloat {
        fx.controller.workspaceManager.withNiriViewportState(for: fx.workspaceId) { state in
            let columns = fx.engine.columns(in: fx.workspaceId)
            state.selectedNodeId = fx.nodes[activeColumn].id
            state.activeColumnIndex = activeColumn
            let activeX = state.columnX(at: activeColumn, columns: columns, gap: fx.gap)
            state.viewOffsetPixels = .static(viewStart - activeX)
        }
        return currentViewStart(fx)
    }

    private func currentViewStart(_ fx: Fixture) -> CGFloat {
        let state = fx.controller.workspaceManager.niriViewportState(for: fx.workspaceId)
        let columns = fx.engine.columns(in: fx.workspaceId)
        return state.targetViewPosPixels(columns: columns, gap: fx.gap)
    }

    private func setWidth(_ fx: Fixture, column columnIndex: Int, percent: CGFloat) {
        fx.controller.workspaceManager.withNiriViewportState(for: fx.workspaceId) { state in
            let column = fx.engine.columns(in: fx.workspaceId)[columnIndex]
            fx.engine.setColumnWidth(
                column,
                change: .setProportion(percent),
                in: fx.workspaceId,
                motion: .disabled,
                state: &state,
                workingFrame: fx.workingFrame,
                gaps: fx.gap
            )
        }
    }

    // MARK: - Fully visible: the anchor survives both grow and shrink

    @Test func fullyVisibleColumnKeepsViewportOnGrow() async {
        guard let fx = await makeFixture(widthFactors: [0.5, 0.3, 0.5, 0.5]) else { return }

        // Column 1 sits fully visible but deliberately off-center.
        let columns = fx.engine.columns(in: fx.workspaceId)
        let columnStart = fx.controller.workspaceManager.niriViewportState(for: fx.workspaceId)
            .columnX(at: 1, columns: columns, gap: fx.gap)
        let parkStart = columnStart - fx.workingFrame.width * 0.1
        let resolvedStart = park(fx, activeColumn: 1, viewStart: parkStart)
        #expect(abs(resolvedStart - parkStart) < 0.5)

        // Growing to 40% keeps the column fully visible from the current anchor.
        setWidth(fx, column: 1, percent: 40)

        #expect(abs(currentViewStart(fx) - parkStart) < 0.5)
    }

    @Test func fullyVisibleColumnKeepsViewportOnShrink() async {
        guard let fx = await makeFixture(widthFactors: [0.5, 0.65, 0.5, 0.5]) else { return }

        let columns = fx.engine.columns(in: fx.workspaceId)
        let columnStart = fx.controller.workspaceManager.niriViewportState(for: fx.workspaceId)
            .columnX(at: 1, columns: columns, gap: fx.gap)
        let parkStart = columnStart - fx.workingFrame.width * 0.2
        let resolvedStart = park(fx, activeColumn: 1, viewStart: parkStart)
        #expect(abs(resolvedStart - parkStart) < 0.5)

        setWidth(fx, column: 1, percent: 35)

        #expect(abs(currentViewStart(fx) - parkStart) < 0.5)
    }

    /// The exact #170 edge-snap capture shape: a leading-edge-snapped column
    /// grows but still fits from that snap — the snap must survive instead of
    /// being replaced by the center snap.
    @Test func leadingEdgeSnapSurvivesGrowThatStillFits() async {
        guard let fx = await makeFixture(widthFactors: [0.65, 0.5, 0.5, 0.5]) else { return }

        // Left-edge snap for column 0: columnX - gap.
        let parkStart = -fx.gap
        let resolvedStart = park(fx, activeColumn: 0, viewStart: parkStart)
        #expect(abs(resolvedStart - parkStart) < 0.5)

        // 95% of the working width still fits inside the viewport from -gap.
        setWidth(fx, column: 0, percent: 95)

        #expect(abs(currentViewStart(fx) - parkStart) < 0.5)
    }

    // MARK: - Clipped by growth: minimal shift, not recenter

    @Test func growThatClipsTrailingEdgeShiftsMinimally() async {
        guard let fx = await makeFixture(widthFactors: [0.5, 0.5, 0.5, 0.5]) else { return }

        // Park so column 1 starts 60% into the viewport: growing it to 65%
        // pushes its trailing edge past the viewport end.
        let columns = fx.engine.columns(in: fx.workspaceId)
        let state = fx.controller.workspaceManager.niriViewportState(for: fx.workspaceId)
        let columnStart = state.columnX(at: 1, columns: columns, gap: fx.gap)
        let parkStart = columnStart - fx.workingFrame.width * 0.6
        let resolvedStart = park(fx, activeColumn: 1, viewStart: parkStart)
        #expect(abs(resolvedStart - parkStart) < 0.5)

        setWidth(fx, column: 1, percent: 65)

        // Minimal restore of full visibility is the trailing-edge snap:
        // columnEnd + gap - viewportWidth. Anything closer to the old center
        // would be a recenter regression.
        let newWidth = fx.engine.columns(in: fx.workspaceId)[1].cachedWidth
        let expectedStart = columnStart + newWidth + fx.gap - fx.workingFrame.width
        #expect(abs(currentViewStart(fx) - expectedStart) < 0.5)
        let centerStart = columnStart + newWidth / 2 - fx.workingFrame.width / 2
        #expect(abs(currentViewStart(fx) - centerStart) > 1.0)
    }

    // MARK: - Over-wide column anchors its leading edge

    @Test func overWideColumnAnchorsLeadingEdge() async {
        guard let fx = await makeFixture(widthFactors: [0.5, 0.5, 0.5, 0.5]) else { return }

        let columns = fx.engine.columns(in: fx.workspaceId)
        let state = fx.controller.workspaceManager.niriViewportState(for: fx.workspaceId)
        let columnStart = state.columnX(at: 1, columns: columns, gap: fx.gap)
        let parkStart = columnStart - fx.workingFrame.width * 0.5
        let resolvedStart = park(fx, activeColumn: 1, viewStart: parkStart)
        #expect(abs(resolvedStart - parkStart) < 0.5)

        // 120% of the working width cannot be fully visible; the leading edge
        // (columnX - gap) is the anchor.
        setWidth(fx, column: 1, percent: 120)

        let expectedStart = columnStart - fx.gap
        #expect(abs(currentViewStart(fx) - expectedStart) < 0.5)
    }
}
