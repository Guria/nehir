// SPDX-FileCopyrightText: 2026 Aleksei Gurianov and Nehir contributors
// SPDX-FileComment: Provenance=nehir-original; See=NOTICE.md
//
// SPDX-License-Identifier: GPL-2.0-only

import ApplicationServices
import CoreGraphics
import Foundation
@testable import Nehir
import Testing

private struct PrepareCreateRejectionSnapshot {
    let windowId: UInt32
    let token: WindowToken?
    let context: String
    let reason: PrepareCreateCandidateRejectionReason
    let parentWindowId: UInt32?
    let hasFloatingTag: Bool?
    let hasDocumentTag: Bool?
    let frame: CGRect?

    init?(_ event: NiriCreateFocusTraceEvent) {
        guard case let .prepareCreateRejected(
            windowId: windowId,
            token: token,
            context: context,
            reason: reason,
            hasWindowInfo: _,
            windowInfoPid: _,
            windowInfoLevel: _,
            windowInfoParentId: parentWindowId,
            windowInfoHasFloatingTag: hasFloatingTag,
            windowInfoHasDocumentTag: hasDocumentTag,
            windowInfoFrame: frame,
            fallbackToken: _,
            hasFallbackAXRef: _,
            createContextSource: _
        ) = event.kind else {
            return nil
        }
        self.windowId = windowId
        self.token = token
        self.context = context
        self.reason = reason
        self.parentWindowId = parentWindowId
        self.hasFloatingTag = hasFloatingTag
        self.hasDocumentTag = hasDocumentTag
        self.frame = frame
    }
}

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
        #expect(controller.axEventHandler.niriCreateFocusTraceSnapshotForTests()
            .compactMap(PrepareCreateRejectionSnapshot.init)
            .contains { rejection in
                rejection.windowId == popupWindowId &&
                    rejection.token == popupToken &&
                    rejection.context == "focused_admission" &&
                    rejection.reason == .unstableWindowServerInfo &&
                    rejection.parentWindowId == 0 &&
                    rejection.frame == .zero
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
                .compactMap(PrepareCreateRejectionSnapshot.init)
                .contains { rejection in
                    rejection.windowId == popupWindowId &&
                        rejection.token == popupToken &&
                        rejection.reason == .untrackedDecision &&
                        rejection.parentWindowId == UInt32(parentWindowId) &&
                        rejection.frame == windowInfo.frame
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
        #expect(controller.axEventHandler.niriCreateFocusTraceSnapshotForTests()
            .compactMap(PrepareCreateRejectionSnapshot.init)
            .contains { rejection in
                rejection.windowId == popupWindowId &&
                    rejection.token == popupToken &&
                    rejection.reason == .untrackedDecision &&
                    rejection.parentWindowId == UInt32(parentWindowId) &&
                    rejection.hasFloatingTag == true &&
                    rejection.hasDocumentTag == false &&
                    rejection.frame == windowInfo.frame
            })
    }

    @Test func focusedStandardWindowCanBeAdmittedWithoutWindowServerFacts() {
        let controller = makeLayoutPlanTestController()
        guard let workspaceId = controller.interactionWorkspace()?.id else {
            Issue.record("Missing focused-create fallback workspace")
            return
        }

        let pid: pid_t = 91_702
        let windowId = 9_172
        let token = WindowToken(pid: pid, windowId: windowId)
        let axRef = makeLayoutPlanTestWindow(windowId: windowId)
        controller.hasStartedServices = true
        controller.axEventHandler.windowInfoProviderIsAuthoritativeForTests = true
        controller.axEventHandler.windowInfoProvider = { _ in nil }
        controller.axEventHandler.focusedWindowRefProvider = { candidatePid in
            candidatePid == pid ? axRef : nil
        }
        controller.axEventHandler.bundleIdProvider = { _ in "com.example.focused-standard-window" }
        controller.axEventHandler.windowFactsProvider = { candidateRef, candidatePid in
            guard candidateRef.windowId == windowId, candidatePid == pid else { return nil }
            return WindowRuleFacts(
                appName: "Focused Standard Window",
                ax: AXWindowFacts(
                    role: kAXWindowRole as String,
                    subrole: kAXStandardWindowSubrole as String,
                    title: "Document",
                    hasCloseButton: true,
                    hasFullscreenButton: true,
                    fullscreenButtonEnabled: true,
                    hasZoomButton: true,
                    hasMinimizeButton: true,
                    appPolicy: .regular,
                    bundleId: "com.example.focused-standard-window",
                    attributeFetchSucceeded: true
                ),
                sizeConstraints: nil,
                windowServer: nil
            )
        }
        controller.axEventHandler.isFullscreenProvider = { _ in false }
        defer {
            controller.axEventHandler.windowInfoProviderIsAuthoritativeForTests = false
            controller.axEventHandler.windowInfoProvider = nil
            controller.axEventHandler.focusedWindowRefProvider = nil
            controller.axEventHandler.bundleIdProvider = nil
            controller.axEventHandler.windowFactsProvider = nil
            controller.axEventHandler.isFullscreenProvider = nil
            controller.axEventHandler.resetDebugStateForTests()
        }

        controller.axEventHandler.handleAppActivation(pid: pid, source: .focusedWindowChanged)

        #expect(controller.workspaceManager.entry(for: token)?.workspaceId == workspaceId)
        #expect(controller.workspaceManager.confirmedManagedFocusToken == token)
        #expect(!controller.workspaceManager.isNonManagedFocusActive)
        #expect(!controller.axEventHandler.niriCreateFocusTraceSnapshotForTests()
            .compactMap(PrepareCreateRejectionSnapshot.init)
            .contains { rejection in
                rejection.token == token && rejection.reason == .unstableWindowServerInfo
            })
    }
}
