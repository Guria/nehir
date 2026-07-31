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
struct QuickTerminalPointerIntentTests {
    private final class FrontedWindows: @unchecked Sendable {
        private(set) var tokens: [WindowToken] = []

        func record(pid: pid_t, windowId: UInt32) {
            tokens.append(WindowToken(pid: pid, windowId: Int(windowId)))
        }

        func reset() {
            tokens.removeAll()
        }
    }

    @Test func appActivationForPointerCandidateReplacesStaleOverlayCloseAnchor() {
        let fronted = FrontedWindows()
        let controller = makeLayoutPlanTestController(
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { pid, windowId, _ in
                    fronted.record(pid: pid, windowId: windowId)
                },
                raiseWindow: { _ in }
            )
        )
        controller.hasStartedServices = true
        defer {
            controller.axEventHandler.windowInfoProviderIsAuthoritativeForTests = false
            controller.axEventHandler.windowInfoProvider = nil
            controller.axEventHandler.windowOrderedInProvider = nil
            controller.axEventHandler.visibleWindowInfoProvider = nil
            controller.axEventHandler.focusedWindowRefProvider = nil
            controller.axEventHandler.isFullscreenProvider = nil
            controller.axEventHandler.frontmostApplicationPidProvider = nil
            controller.axEventHandler.resetDebugStateForTests()
        }
        guard let workspaceId = controller.interactionWorkspace()?.id,
              let monitorId = controller.workspaceManager.monitorId(for: workspaceId)
        else {
            Issue.record("Missing active workspace for pointer-intent fixture")
            return
        }

        let ghosttyPid: pid_t = 82_101
        let qutebrowserPid: pid_t = 82_102
        let overlayWindowId = 82_001
        let overlayInfo = makeQuickTerminalWindowInfoForTests(
            pid: ghosttyPid,
            windowId: overlayWindowId
        )
        controller.axEventHandler.windowInfoProviderIsAuthoritativeForTests = true
        controller.axEventHandler.windowInfoProvider = { windowId in
            windowId == overlayInfo.id ? overlayInfo : nil
        }
        controller.axEventHandler.windowOrderedInProvider = { windowId in
            windowId == overlayInfo.id ? true : nil
        }
        controller.axEventHandler.visibleWindowInfoProvider = { [overlayInfo] }

        let staleGhosttyToken = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 82_002),
            pid: ghosttyPid,
            windowId: 82_002,
            to: workspaceId
        )
        let clickedQutebrowserToken = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 82_003),
            pid: qutebrowserPid,
            windowId: 82_003,
            to: workspaceId,
            mode: .floating
        )
        guard let staleGhosttyEntry = controller.workspaceManager.entry(for: staleGhosttyToken) else {
            Issue.record("Missing managed entries for pointer-intent fixture")
            return
        }

        #expect(controller.workspaceManager.setManagedFocus(
            staleGhosttyToken,
            in: workspaceId,
            onMonitor: monitorId
        ))
        controller.axEventHandler.handleManagedAppActivation(
            entry: staleGhosttyEntry,
            isWorkspaceActive: true,
            appFullscreen: false,
            source: .focusedWindowChanged
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

        // WindowServer hit testing can return both the floating window and the
        // tiled window beneath it. The activation echo identifies which candidate
        // actually received the click.
        controller.axEventHandler.recordManagedPointerFocusIntent([
            clickedQutebrowserToken,
            staleGhosttyToken
        ])
        controller.axEventHandler.focusedWindowRefProvider = { pid in
            pid == qutebrowserPid
                ? AXWindowRef(
                    element: AXUIElementCreateSystemWide(),
                    windowId: clickedQutebrowserToken.windowId
                )
                : nil
        }
        controller.axEventHandler.isFullscreenProvider = { _ in false }
        controller.axEventHandler.handleAppActivation(
            pid: qutebrowserPid,
            source: .workspaceDidActivateApplication,
            origin: .external
        )
        #expect(controller.workspaceManager.confirmedManagedFocusToken == clickedQutebrowserToken)

        // Make the internal confirmation stale while AX and the frontmost-app
        // boundary still report the pointer-selected qutebrowser window. Overlay
        // teardown must adopt that already-focused anchor without refocusing it.
        #expect(controller.workspaceManager.setManagedFocus(
            staleGhosttyToken,
            in: workspaceId,
            onMonitor: monitorId
        ))
        controller.axEventHandler.frontmostApplicationPidProvider = { qutebrowserPid }

        fronted.reset()
        controller.axEventHandler.handleRemoved(pid: ghosttyPid, winId: overlayWindowId)

        #expect(fronted.tokens.isEmpty)
        #expect(controller.workspaceManager.activeFocusRequestToken == nil)
        #expect(controller.workspaceManager.confirmedManagedFocusToken == clickedQutebrowserToken)
    }
}
