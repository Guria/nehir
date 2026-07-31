// SPDX-FileCopyrightText: 2026 Aleksei Gurianov and Nehir contributors
// SPDX-FileComment: Provenance=nehir-original; See=NOTICE.md
//
// SPDX-License-Identifier: GPL-2.0-only

import ApplicationServices
import CoreGraphics
import Foundation
@testable import Nehir
import Testing

private let replacementFocusBundleId = "com.example.native-tabs"

private enum ReplacementViewportTarget {
    case confirmedWindow
    case rightNeighbor
}

private struct ReplacementFixtureWindows {
    let confirmedToken: WindowToken
    let peerOneToken: WindowToken
    let peerTwoToken: WindowToken
    let transientToken: WindowToken
    let rightNeighborToken: WindowToken
    let transientInfo: WindowServerInfo
}

private struct ReplacementFixtureNodes {
    let confirmedNode: NiriWindow
    let rightNeighborNode: NiriWindow
}

private struct ReplacementFixtureContext {
    let controller: WMController
    let engine: NiriLayoutEngine
    let monitor: Monitor
    let monitorId: Monitor.ID
    let workspaceId: WorkspaceDescriptor.ID
}

private struct ReplacementFocusSnapshot {
    let nodeId: NodeId
    let selectedNodeId: NodeId?
    let activeColumnIndex: Int
    let columnIndex: Int
    let viewStart: CGFloat
    let visibility: ColumnVisibility
}

@MainActor
private struct ReplacementFocusFixture {
    let controller: WMController
    let engine: NiriLayoutEngine
    let monitor: Monitor
    let workspaceId: WorkspaceDescriptor.ID
    let confirmedToken: WindowToken
    let rightNeighborToken: WindowToken
    let transientToken: WindowToken

    func snapshot(for token: WindowToken) -> ReplacementFocusSnapshot? {
        guard let node = engine.findNode(for: token),
              let column = engine.column(of: node),
              let columnIndex = engine.columnIndex(of: column, in: workspaceId)
        else {
            return nil
        }
        let state = controller.workspaceManager.niriViewportState(for: workspaceId)
        let columns = engine.columns(in: workspaceId)
        let gap = controller.gapSize(for: monitor)
        let viewStart = state.targetViewPosPixels(columns: columns, gap: gap)
        let context = engine.makeViewportSnapContext(
            columns: columns,
            state: state,
            workingFrame: controller.insetWorkingFrame(for: monitor),
            gaps: gap,
            intentionallyDoesNotFillViewport: engine.loneWindowIntentionallyDoesNotFillViewport(in: workspaceId)
        )
        return ReplacementFocusSnapshot(
            nodeId: node.id,
            selectedNodeId: state.selectedNodeId,
            activeColumnIndex: state.activeColumnIndex,
            columnIndex: columnIndex,
            viewStart: viewStart,
            visibility: context.visibility(of: columnIndex, viewportOffset: viewStart, in: state)
        )
    }

    func removeTransientWindow() async {
        controller.axEventHandler.cgsEventObserver(
            CGSEventObserver.shared,
            didReceive: .destroyed(windowId: UInt32(transientToken.windowId), spaceId: 0)
        )
        #expect(controller.workspaceManager.entry(for: transientToken) != nil)
        #expect(
            controller.axEventHandler.memoryDebugSnapshot()
                .pendingCreatedWindowRetryTaskCount == 0
        )
        controller.axEventHandler.flushPendingManagedReplacementEventsForTests()
        await waitForLayoutPlanRefreshWork(on: controller)
    }
}

@MainActor
struct ReplacementFocusReconcileTests {
    @Test func settledReplacementRemovalRevealsParkedConfirmedFocus() async {
        guard let fixture = await makeReplacementFocusFixture(viewportTarget: .rightNeighbor),
              let before = fixture.snapshot(for: fixture.confirmedToken)
        else {
            Issue.record("Missing parked managed-replacement fixture")
            return
        }
        guard case .parked = before.visibility else {
            Issue.record("Confirmed focus must begin parked to exercise automatic reveal")
            return
        }
        #expect(fixture.controller.workspaceManager.confirmedManagedFocusToken == fixture.confirmedToken)
        #expect(fixture.controller.workspaceManager.preferredWorkspaceFocusToken(in: fixture.workspaceId) == fixture
            .rightNeighborToken)

        await fixture.removeTransientWindow()

        guard let after = fixture.snapshot(for: fixture.confirmedToken) else {
            Issue.record("Missing confirmed window after replacement cleanup")
            return
        }
        let pixel = 1.0 / max(fixture.engine.displayScale(in: fixture.workspaceId), 1.0)
        #expect(fixture.controller.workspaceManager.entry(for: fixture.transientToken) == nil)
        #expect(fixture.engine.findNode(for: fixture.transientToken) == nil)
        #expect(after.selectedNodeId == after.nodeId)
        #expect(after.activeColumnIndex == after.columnIndex)
        #expect(fixture.controller.workspaceManager.preferredWorkspaceFocusToken(in: fixture.workspaceId) == fixture
            .confirmedToken)
        #expect(abs(after.viewStart - before.viewStart) > pixel)
        if case .parked = after.visibility {
            Issue.record("Confirmed focus remained parked after replacement cleanup")
        }
    }

    @Test func settledReplacementRemovalDoesNotMoveVisibleConfirmedFocus() async {
        guard let fixture = await makeReplacementFocusFixture(viewportTarget: .confirmedWindow),
              let before = fixture.snapshot(for: fixture.confirmedToken)
        else {
            Issue.record("Missing visible managed-replacement fixture")
            return
        }
        guard case .fullyVisible = before.visibility else {
            Issue.record("Confirmed focus must begin fully visible to exercise the no-op path")
            return
        }

        await fixture.removeTransientWindow()

        guard let after = fixture.snapshot(for: fixture.confirmedToken) else {
            Issue.record("Missing visible confirmed window after replacement cleanup")
            return
        }
        let pixel = 1.0 / max(fixture.engine.displayScale(in: fixture.workspaceId), 1.0)
        #expect(after.selectedNodeId == after.nodeId)
        #expect(after.activeColumnIndex == after.columnIndex)
        #expect(fixture.controller.workspaceManager.preferredWorkspaceFocusToken(in: fixture.workspaceId) == fixture
            .confirmedToken)
        #expect(abs(after.viewStart - before.viewStart) <= pixel)
        #expect(after.visibility == .fullyVisible)
    }
}

@MainActor
private func makeReplacementFocusFixture(
    viewportTarget: ReplacementViewportTarget
) async -> ReplacementFocusFixture? {
    let monitor = makeLayoutPlanTestMonitor(width: 1_200, height: 800)
    let controller = makeLayoutPlanTestController(monitors: [monitor])
    guard let workspaceId = controller.interactionWorkspace()?.id,
          let monitorId = controller.workspaceManager.monitorId(for: workspaceId)
    else {
        return nil
    }

    controller.appInfoCache.storeInfoForTests(pid: getpid(), bundleId: replacementFocusBundleId)
    controller.axEventHandler.bundleIdProvider = { _ in replacementFocusBundleId }
    controller.enableNiriLayout(revealStyle: .auto)
    await waitForLayoutPlanRefreshWork(on: controller)
    guard let engine = controller.niriEngine else { return nil }

    let context = ReplacementFixtureContext(
        controller: controller,
        engine: engine,
        monitor: monitor,
        monitorId: monitorId,
        workspaceId: workspaceId
    )
    let windows = addReplacementFixtureWindows(on: controller, workspaceId: workspaceId)
    let nodes = addReplacementFixtureNodes(windows: windows, engine: engine, workspaceId: workspaceId)
    positionReplacementFixtureViewport(
        target: viewportTarget,
        windows: windows,
        nodes: nodes,
        context: context
    )
    controller.axEventHandler.windowInfoProviderIsAuthoritativeForTests = true
    controller.axEventHandler.windowInfoProvider = { windowId in
        windowId == UInt32(windows.transientToken.windowId) ? windows.transientInfo : nil
    }
    return ReplacementFocusFixture(
        controller: controller,
        engine: engine,
        monitor: monitor,
        workspaceId: workspaceId,
        confirmedToken: windows.confirmedToken,
        rightNeighborToken: windows.rightNeighborToken,
        transientToken: windows.transientToken
    )
}

@MainActor
private func addReplacementFixtureWindows(
    on controller: WMController,
    workspaceId: WorkspaceDescriptor.ID
) -> ReplacementFixtureWindows {
    let confirmedToken = addReplacementPlainWindow(
        on: controller,
        workspaceId: workspaceId,
        windowId: 97_001,
        pid: getpid()
    )
    let peerOneToken = addReplacementPlainWindow(
        on: controller,
        workspaceId: workspaceId,
        windowId: 97_002,
        pid: 97_102
    )
    let peerTwoToken = addReplacementPlainWindow(
        on: controller,
        workspaceId: workspaceId,
        windowId: 97_003,
        pid: 97_103
    )
    let transientInfo = makeReplacementWindowInfo(windowId: 97_004)
    let transientToken = controller.workspaceManager.addWindow(
        makeLayoutPlanTestWindow(windowId: Int(transientInfo.id)),
        pid: getpid(),
        windowId: Int(transientInfo.id),
        to: workspaceId,
        managedReplacementMetadata: makeReplacementMetadata(
            workspaceId: workspaceId,
            windowServer: transientInfo
        )
    )
    let rightNeighborToken = addReplacementPlainWindow(
        on: controller,
        workspaceId: workspaceId,
        windowId: 97_005,
        pid: 97_105
    )
    return ReplacementFixtureWindows(
        confirmedToken: confirmedToken,
        peerOneToken: peerOneToken,
        peerTwoToken: peerTwoToken,
        transientToken: transientToken,
        rightNeighborToken: rightNeighborToken,
        transientInfo: transientInfo
    )
}

private func addReplacementFixtureNodes(
    windows: ReplacementFixtureWindows,
    engine: NiriLayoutEngine,
    workspaceId: WorkspaceDescriptor.ID
) -> ReplacementFixtureNodes {
    let confirmed = engine.addWindow(token: windows.confirmedToken, to: workspaceId, afterSelection: nil)
    let peerOne = engine.addWindow(token: windows.peerOneToken, to: workspaceId, afterSelection: confirmed.id)
    let peerTwo = engine.addWindow(token: windows.peerTwoToken, to: workspaceId, afterSelection: peerOne.id)
    let transient = engine.addWindow(token: windows.transientToken, to: workspaceId, afterSelection: peerTwo.id)
    let rightNeighbor = engine.addWindow(
        token: windows.rightNeighborToken,
        to: workspaceId,
        afterSelection: transient.id
    )
    return ReplacementFixtureNodes(confirmedNode: confirmed, rightNeighborNode: rightNeighbor)
}

@MainActor
private func positionReplacementFixtureViewport(
    target: ReplacementViewportTarget,
    windows: ReplacementFixtureWindows,
    nodes: ReplacementFixtureNodes,
    context: ReplacementFixtureContext
) {
    let gap = context.controller.gapSize(for: context.monitor)
    let workingFrame = context.controller.insetWorkingFrame(for: context.monitor)
    _ = context.engine.calculateLayout(
        state: context.controller.workspaceManager.niriViewportState(for: context.workspaceId),
        workspaceId: context.workspaceId,
        monitorFrame: workingFrame,
        gaps: (horizontal: gap, vertical: gap)
    )
    let viewportNode = target == .confirmedWindow ? nodes.confirmedNode : nodes.rightNeighborNode
    var state = context.controller.workspaceManager.niriViewportState(for: context.workspaceId)
    context.engine.activateWindow(viewportNode.id)
    state.selectedNodeId = viewportNode.id
    context.engine.ensureSelectionVisible(
        node: viewportNode,
        in: context.workspaceId,
        motion: context.controller.motionPolicy.snapshot(),
        state: &state,
        workingFrame: workingFrame,
        gaps: gap,
        revealTrigger: .explicitNavigation
    )
    state.viewOffsetPixels = .static(state.viewOffsetPixels.target())
    _ = context.controller.workspaceManager.applySessionPatch(
        .init(workspaceId: context.workspaceId, viewportState: state)
    )
    _ = context.controller.workspaceManager.setManagedFocus(
        windows.confirmedToken,
        in: context.workspaceId,
        onMonitor: context.monitorId
    )
    if target == .rightNeighbor {
        _ = context.controller.workspaceManager.syncWorkspaceFocus(
            windows.rightNeighborToken,
            in: context.workspaceId
        )
    }
}

@MainActor
private func addReplacementPlainWindow(
    on controller: WMController,
    workspaceId: WorkspaceDescriptor.ID,
    windowId: Int,
    pid: pid_t
) -> WindowToken {
    controller.workspaceManager.addWindow(
        makeLayoutPlanTestWindow(windowId: windowId),
        pid: pid,
        windowId: windowId,
        to: workspaceId
    )
}

private func makeReplacementWindowInfo(windowId: Int) -> WindowServerInfo {
    var info = WindowServerInfo(
        id: UInt32(windowId),
        pid: getpid(),
        level: 0,
        frame: CGRect(x: 80, y: 80, width: 900, height: 640)
    )
    info.parentId = 97_000
    info.title = "repo - shell (temporary tab identity)"
    return info
}

private func makeReplacementMetadata(
    workspaceId: WorkspaceDescriptor.ID,
    windowServer: WindowServerInfo
) -> ManagedReplacementMetadata {
    ManagedReplacementMetadata(
        bundleId: replacementFocusBundleId,
        workspaceId: workspaceId,
        mode: .tiling,
        role: kAXWindowRole as String,
        subrole: kAXStandardWindowSubrole as String,
        title: windowServer.title,
        windowLevel: windowServer.level,
        parentWindowId: windowServer.parentId == 0 ? nil : windowServer.parentId,
        frame: windowServer.frame
    )
}
