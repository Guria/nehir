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
struct FocusedCreateStabilizationTests {
    @Test func placeholderWindowServerRecordDefersAdmissionUntilParentedFactsAreCoherent() async {
        var frontedTokens: [WindowToken] = []
        let controller = makeLayoutPlanTestController(
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { pid, windowId, _ in
                    frontedTokens.append(WindowToken(pid: pid, windowId: Int(windowId)))
                },
                raiseWindow: { _ in }
            )
        )
        guard let workspaceId = controller.interactionWorkspace()?.id,
              let monitorId = controller.workspaceManager.monitorId(for: workspaceId)
        else {
            Issue.record("Missing focused-create stabilization workspace")
            return
        }

        let pid: pid_t = 91_701
        let parentWindowId = 9_170
        let popupWindowId: UInt32 = 9_171
        let parentToken = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: parentWindowId),
            pid: pid,
            windowId: parentWindowId,
            to: workspaceId
        )
        #expect(controller.workspaceManager.setManagedFocus(
            parentToken,
            in: workspaceId,
            onMonitor: monitorId
        ))

        var windowInfo = WindowServerInfo(
            id: popupWindowId,
            pid: pid,
            level: 0,
            frame: .zero
        )
        let popupAXRef = AXWindowRef(
            element: AXUIElementCreateSystemWide(),
            windowId: Int(popupWindowId)
        )
        var subscriptions: [UInt32] = []
        var relayoutReasons: [RefreshReason] = []

        controller.hasStartedServices = true
        controller.axEventHandler.windowInfoProviderIsAuthoritativeForTests = true
        controller.axEventHandler.windowInfoProvider = { windowId in
            windowId == popupWindowId ? windowInfo : nil
        }
        controller.axEventHandler.axWindowRefProvider = { windowId, candidatePid in
            guard windowId == popupWindowId, candidatePid == pid else { return nil }
            return popupAXRef
        }
        controller.axEventHandler.focusedWindowRefProvider = { candidatePid in
            candidatePid == pid ? popupAXRef : nil
        }
        controller.axEventHandler.bundleIdProvider = { _ in "com.example.parented-popup" }
        controller.axEventHandler.windowFactsProvider = { _, _ in
            WindowRuleFacts(
                appName: "Parented Popup",
                ax: AXWindowFacts(
                    role: kAXWindowRole as String,
                    subrole: kAXDialogSubrole as String,
                    title: "Profile Switcher",
                    hasCloseButton: false,
                    hasFullscreenButton: false,
                    fullscreenButtonEnabled: nil,
                    hasZoomButton: false,
                    hasMinimizeButton: false,
                    appPolicy: .regular,
                    bundleId: "com.example.parented-popup",
                    attributeFetchSucceeded: true
                ),
                sizeConstraints: nil,
                windowServer: windowInfo
            )
        }
        controller.axEventHandler.isFullscreenProvider = { _ in false }
        controller.axEventHandler.windowSubscriptionHandler = { subscriptions.append(contentsOf: $0) }
        controller.layoutRefreshController.resetDebugState()
        controller.layoutRefreshController.debugHooks.onRelayout = { reason, _ in
            relayoutReasons.append(reason)
            return false
        }
        defer {
            controller.axEventHandler.resetDebugStateForTests()
            controller.layoutRefreshController.resetDebugState()
        }

        controller.axEventHandler.handleAppActivation(pid: pid, source: .focusedWindowChanged)

        let popupToken = WindowToken(pid: pid, windowId: Int(popupWindowId))
        #expect(controller.workspaceManager.entry(for: popupToken) == nil)
        #expect(controller.workspaceManager.confirmedManagedFocusToken == parentToken)
        #expect(controller.workspaceManager.isNonManagedFocusActive)
        #expect(frontedTokens.isEmpty)
        #expect(subscriptions.isEmpty)
        #expect(relayoutReasons.isEmpty)
        #expect(controller.axEventHandler.niriCreateFocusTraceSnapshotForTests().contains { event in
            if case let .prepareCreateRejected(
                windowId,
                token,
                context,
                reason,
                _,
                _,
                _,
                parentId,
                _,
                _,
                frame,
                _,
                _,
                _
            ) = event.kind {
                return windowId == popupWindowId &&
                    token == popupToken &&
                    context == "focused_admission" &&
                    reason == .unstableWindowServerInfo &&
                    parentId == 0 &&
                    frame == .zero
            }
            return false
        })

        windowInfo = WindowServerInfo(
            id: popupWindowId,
            pid: pid,
            level: 0,
            frame: CGRect(x: 360, y: 220, width: 328, height: 402),
            tags: 0x2,
            parentId: UInt32(parentWindowId)
        )

        for _ in 0 ..< 300 {
            let classifiedAsUnmanaged = controller.axEventHandler
                .niriCreateFocusTraceSnapshotForTests()
                .contains { event in
                    if case let .prepareCreateRejected(
                        windowId,
                        token,
                        _,
                        reason,
                        _,
                        _,
                        _,
                        parentId,
                        _,
                        _,
                        frame,
                        _,
                        _,
                        _
                    ) = event.kind {
                        return windowId == popupWindowId &&
                            token == popupToken &&
                            reason == .untrackedDecision &&
                            parentId == UInt32(parentWindowId) &&
                            frame == windowInfo.frame
                    }
                    return false
                }
            if classifiedAsUnmanaged { break }
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(controller.workspaceManager.entry(for: popupToken) == nil)
        #expect(controller.workspaceManager.confirmedManagedFocusToken == nil)
        #expect(controller.workspaceManager.isNonManagedFocusActive)
        #expect(frontedTokens.isEmpty)
        #expect(subscriptions.isEmpty)
        #expect(!relayoutReasons.contains(.axWindowCreated))
        #expect(controller.axEventHandler.niriCreateFocusTraceSnapshotForTests().contains { event in
            if case let .prepareCreateRejected(
                windowId,
                token,
                _,
                reason,
                _,
                _,
                _,
                parentId,
                hasFloatingTag,
                hasDocumentTag,
                frame,
                _,
                _,
                _
            ) = event.kind {
                return windowId == popupWindowId &&
                    token == popupToken &&
                    reason == .untrackedDecision &&
                    parentId == UInt32(parentWindowId) &&
                    hasFloatingTag == true &&
                    hasDocumentTag == false &&
                    frame == windowInfo.frame
            }
            return false
        })
    }
}
