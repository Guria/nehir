// SPDX-FileCopyrightText: 2026 Aleksei Gurianov and Nehir contributors
// SPDX-FileComment: Provenance=nehir-original; See=NOTICE.md
//
// SPDX-License-Identifier: GPL-2.0-only

import ApplicationServices
import CoreGraphics
import Foundation
@testable import Nehir
import Testing

@MainActor
struct QuickTerminalStartupLifecycleTests {
    @Test func visibleOverlayIsDiscoveredBeforeItsOwnerActivationIsHandled() {
        let controller = makeLayoutPlanTestController()
        guard let sourceWorkspaceId = controller.interactionWorkspace()?.id,
              let targetWorkspaceId = controller.workspaceManager.workspaceId(for: "2", createIfMissing: false),
              let monitorId = controller.workspaceManager.monitorId(for: sourceWorkspaceId)
        else {
            Issue.record("Missing workspaces for startup overlay fixture")
            return
        }

        let ghosttyPid: pid_t = 99_101
        let targetPid: pid_t = 99_102
        let sourceToken = controller.workspaceManager.addWindow(
            makeLayoutPlanTestWindow(windowId: 99_001),
            pid: ghosttyPid,
            windowId: 99_001,
            to: sourceWorkspaceId
        )
        let targetToken = controller.workspaceManager.addWindow(
            makeLayoutPlanTestWindow(windowId: 99_002),
            pid: targetPid,
            windowId: 99_002,
            to: targetWorkspaceId
        )
        guard let targetEntry = controller.workspaceManager.entry(for: targetToken) else {
            Issue.record("Missing cross-app target entry")
            return
        }
        #expect(controller.workspaceManager.setManagedFocus(
            sourceToken,
            in: sourceWorkspaceId,
            onMonitor: monitorId
        ))

        let overlayInfo = makeQuickTerminalWindowInfoForTests(pid: ghosttyPid, windowId: 99_003)
        controller.hasStartedServices = true
        controller.axEventHandler.visibleWindowInfoProvider = { [overlayInfo] }
        controller.axEventHandler.windowInfoProviderIsAuthoritativeForTests = true
        controller.axEventHandler.windowInfoProvider = { windowId in
            windowId == overlayInfo.id ? overlayInfo : nil
        }
        controller.axEventHandler.windowOrderedInProvider = { windowId in
            windowId == overlayInfo.id ? true : nil
        }
        controller.axEventHandler.focusedWindowRefProvider = { pid in
            pid == ghosttyPid
                ? AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: sourceToken.windowId)
                : nil
        }
        controller.axEventHandler.bundleIdProvider = { pid in
            pid == ghosttyPid ? "com.mitchellh.ghostty" : "com.example.target"
        }
        controller.axEventHandler.windowFactsProvider = { axRef, pid in
            if axRef.windowId == Int(overlayInfo.id) {
                return makeQuickTerminalFactsForTests(
                    pid: ghosttyPid,
                    windowId: Int(overlayInfo.id),
                    windowServer: overlayInfo
                )
            }
            return standardWindowFacts(pid: pid, windowId: axRef.windowId)
        }
        controller.axEventHandler.isFullscreenProvider = { _ in false }
        defer {
            controller.axEventHandler.visibleWindowInfoProvider = nil
            controller.axEventHandler.windowInfoProvider = nil
            controller.axEventHandler.windowInfoProviderIsAuthoritativeForTests = false
            controller.axEventHandler.windowOrderedInProvider = nil
            controller.axEventHandler.focusedWindowRefProvider = nil
            controller.axEventHandler.bundleIdProvider = nil
            controller.axEventHandler.windowFactsProvider = nil
            controller.axEventHandler.isFullscreenProvider = nil
            controller.axEventHandler.resetDebugStateForTests()
        }

        // The overlay existed before Nehir started, so no create/admission event
        // has armed its pid. Activation sampling must discover it from the live
        // WindowServer snapshot before focus arbitration continues.
        controller.axEventHandler.handleAppActivation(
            pid: ghosttyPid,
            source: .focusedWindowChanged
        )
        controller.axEventHandler.handleManagedAppActivation(
            entry: targetEntry,
            isWorkspaceActive: false,
            appFullscreen: false,
            source: .workspaceDidActivateApplication
        )

        #expect(controller.axEventHandler.niriCreateFocusTraceSnapshotForTests().contains { event in
            if case let .followFocusToParkedWindow(token, workspaceId, decision) = event.kind {
                return token == targetToken
                    && workspaceId == targetWorkspaceId
                    && decision == "skip reason=causeless_external_overlay_close"
            }
            return false
        })
    }

    @Test func recognizedOverlaySkipsFocusedWindowChurnScanButSamplesAppActivation() {
        let controller = makeLayoutPlanTestController()
        let ghosttyPid: pid_t = 99_103
        let overlayWindowId = 99_004
        let overlayInfo = makeQuickTerminalWindowInfoForTests(
            pid: ghosttyPid,
            windowId: overlayWindowId
        )
        controller.axEventHandler.armOverlayCapabilityIfNeeded(
            source: .builtInRule("ghosttyQuickTerminalOverlay"),
            token: WindowToken(pid: ghosttyPid, windowId: overlayWindowId),
            facts: makeQuickTerminalFactsForTests(
                pid: ghosttyPid,
                windowId: overlayWindowId,
                windowServer: overlayInfo
            )
        )
        controller.axEventHandler.windowInfoProviderIsAuthoritativeForTests = true
        controller.axEventHandler.windowInfoProvider = { windowId in
            windowId == overlayInfo.id ? overlayInfo : nil
        }
        controller.axEventHandler.windowOrderedInProvider = { windowId in
            windowId == overlayInfo.id ? true : nil
        }
        var visibleWindowScanCount = 0
        controller.axEventHandler.visibleWindowInfoProvider = {
            visibleWindowScanCount += 1
            return [overlayInfo]
        }
        defer {
            controller.axEventHandler.windowInfoProviderIsAuthoritativeForTests = false
            controller.axEventHandler.windowInfoProvider = nil
            controller.axEventHandler.windowOrderedInProvider = nil
            controller.axEventHandler.visibleWindowInfoProvider = nil
            controller.axEventHandler.resetDebugStateForTests()
        }

        controller.axEventHandler.handleAppActivation(
            pid: ghosttyPid,
            source: .focusedWindowChanged
        )
        #expect(visibleWindowScanCount == 0)

        controller.axEventHandler.handleAppActivation(
            pid: ghosttyPid,
            source: .workspaceDidActivateApplication
        )
        #expect(visibleWindowScanCount == 1)
    }

    private func standardWindowFacts(pid: pid_t, windowId: Int) -> WindowRuleFacts {
        WindowRuleFacts(
            appName: "Ghostty",
            ax: AXWindowFacts(
                role: kAXWindowRole as String,
                subrole: kAXStandardWindowSubrole as String,
                title: "Terminal",
                hasCloseButton: true,
                hasFullscreenButton: true,
                fullscreenButtonEnabled: true,
                hasZoomButton: true,
                hasMinimizeButton: true,
                appPolicy: .regular,
                bundleId: "com.mitchellh.ghostty",
                attributeFetchSucceeded: true
            ),
            sizeConstraints: nil,
            windowServer: WindowServerInfo(
                id: UInt32(windowId),
                pid: pid,
                level: 0,
                frame: CGRect(x: 100, y: 100, width: 900, height: 640)
            )
        )
    }
}
