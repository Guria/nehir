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
        defer { controller.axEventHandler.resetDebugStateForTests() }
        guard let workspaceId = controller.interactionWorkspace()?.id,
              let monitorId = controller.workspaceManager.monitorId(for: workspaceId)
        else {
            Issue.record("Missing active workspace for pointer-intent fixture")
            return
        }

        let ghosttyPid: pid_t = 82_101
        let qutebrowserPid: pid_t = 82_102
        let overlayWindowId = 82_001
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
            facts: quickTerminalFacts(pid: ghosttyPid, windowId: overlayWindowId)
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

        fronted.reset()
        controller.axEventHandler.handleRemoved(pid: ghosttyPid, winId: overlayWindowId)

        #expect(fronted.tokens.isEmpty)
        #expect(controller.workspaceManager.activeFocusRequestToken == nil)
        #expect(controller.workspaceManager.confirmedManagedFocusToken == clickedQutebrowserToken)
    }

    private func quickTerminalFacts(pid: pid_t, windowId: Int) -> WindowRuleFacts {
        var windowServer = WindowServerInfo(
            id: UInt32(windowId),
            pid: pid,
            level: 3,
            frame: CGRect(x: 0, y: 40, width: 1_920, height: 1_000)
        )
        windowServer.tags = 0x2
        return WindowRuleFacts(
            appName: "Ghostty",
            ax: AXWindowFacts(
                role: kAXWindowRole as String,
                subrole: kAXFloatingWindowSubrole as String,
                title: "Terminal",
                hasCloseButton: true,
                hasFullscreenButton: false,
                fullscreenButtonEnabled: nil,
                hasZoomButton: true,
                hasMinimizeButton: true,
                appPolicy: .regular,
                bundleId: "com.mitchellh.ghostty",
                attributeFetchSucceeded: true
            ),
            sizeConstraints: nil,
            windowServer: windowServer
        )
    }
}
