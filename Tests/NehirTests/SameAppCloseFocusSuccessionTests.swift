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
private final class SameAppEnumerationGate {
    private(set) var started = false
    private var continuation: CheckedContinuation<AXManager.PerAppWindowEnumeration, Never>?

    func wait() async -> AXManager.PerAppWindowEnumeration {
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }

    func resume(returning result: AXManager.PerAppWindowEnumeration) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

@MainActor
private struct SameAppSuccessionFixture {
    let controller: WMController
    let pid: pid_t
    let predecessorToken: WindowToken
    let successorToken: WindowToken

    func tearDown() {
        controller.axManager.perAppWindowEnumerationOverrideForTests = nil
        controller.axEventHandler.visibleWindowInfoProvider = nil
        controller.axEventHandler.focusedWindowRefProvider = nil
        controller.axEventHandler.bundleIdProvider = nil
        controller.axEventHandler.windowFactsProvider = nil
        controller.axEventHandler.isFullscreenProvider = nil
        controller.axEventHandler.resetDebugStateForTests()
    }
}

@MainActor
struct SameAppCloseFocusSuccessionTests {
    @Test func missingPredecessorDoesNotPreconfirmSystemSelectedSuccessor() async {
        guard let fixture = makeFixture() else { return }
        defer { fixture.tearDown() }
        fixture.controller.axManager.perAppWindowEnumerationOverrideForTests = { pid in
            #expect(pid == fixture.pid)
            return .success([self.enumeratedWindow(fixture.successorToken)])
        }

        fixture.controller.axEventHandler.handleAppActivation(
            pid: fixture.pid,
            source: .focusedWindowChanged
        )
        await waitUntil {
            self.hasFocusDecision(
                fixture.controller,
                token: fixture.successorToken,
                containing: "same_pid_close_succession_preconfirm"
            )
        }

        #expect(hasFocusDecision(
            fixture.controller,
            token: fixture.successorToken,
            containing: "same_pid_close_succession_preconfirm"
        ))
        #expect(fixture.controller.workspaceManager.confirmedManagedFocusToken == fixture.predecessorToken)
        #expect(fixture.controller.workspaceManager.activeFocusRequestToken == nil)
    }

    @Test func livePredecessorAllowsOrdinarySameAppWindowSwitch() async {
        guard let fixture = makeFixture() else { return }
        defer { fixture.tearDown() }
        fixture.controller.axManager.perAppWindowEnumerationOverrideForTests = { _ in
            .success([
                self.enumeratedWindow(fixture.predecessorToken),
                self.enumeratedWindow(fixture.successorToken)
            ])
        }

        fixture.controller.axEventHandler.handleAppActivation(
            pid: fixture.pid,
            source: .focusedWindowChanged
        )
        await waitUntil {
            fixture.controller.workspaceManager.confirmedManagedFocusToken == fixture.successorToken
        }

        #expect(fixture.controller.workspaceManager.confirmedManagedFocusToken == fixture.successorToken)
        #expect(hasFocusDecision(
            fixture.controller,
            token: fixture.successorToken,
            containing: "same_pid_predecessor_alive"
        ))
    }

    @Test func existingNonManagedInteractionBypassesLivenessProbe() async {
        guard let fixture = makeFixture() else { return }
        defer { fixture.tearDown() }
        var enumerationCount = 0
        fixture.controller.axManager.perAppWindowEnumerationOverrideForTests = { _ in
            enumerationCount += 1
            return .failed
        }
        _ = fixture.controller.workspaceManager.enterNonManagedFocus(
            appFullscreen: false,
            preserveFocusedToken: true
        )

        fixture.controller.axEventHandler.handleAppActivation(
            pid: fixture.pid,
            source: .focusedWindowChanged
        )
        await waitUntil {
            fixture.controller.workspaceManager.confirmedManagedFocusToken == fixture.successorToken
        }

        #expect(enumerationCount == 0)
        #expect(fixture.controller.workspaceManager.confirmedManagedFocusToken == fixture.successorToken)
    }

    @Test func interactionBeginningDuringProbeRetriesTheObservedSuccessor() async {
        guard let fixture = makeFixture() else { return }
        defer { fixture.tearDown() }
        let gate = SameAppEnumerationGate()
        fixture.controller.axManager.perAppWindowEnumerationOverrideForTests = { _ in
            await gate.wait()
        }

        fixture.controller.axEventHandler.handleAppActivation(
            pid: fixture.pid,
            source: .focusedWindowChanged
        )
        await waitUntil { gate.started }
        _ = fixture.controller.workspaceManager.enterNonManagedFocus(
            appFullscreen: false,
            preserveFocusedToken: true
        )
        gate.resume(returning: .success([
            enumeratedWindow(fixture.predecessorToken),
            enumeratedWindow(fixture.successorToken)
        ]))
        await waitUntil {
            fixture.controller.workspaceManager.confirmedManagedFocusToken == fixture.successorToken
        }

        #expect(fixture.controller.workspaceManager.confirmedManagedFocusToken == fixture.successorToken)
        #expect(hasFocusDecision(
            fixture.controller,
            token: fixture.successorToken,
            containing: "same_pid_nonmanaged_interaction"
        ))
    }

    private func makeFixture() -> SameAppSuccessionFixture? {
        let controller = makeLayoutPlanTestController()
        guard let workspaceId = controller.interactionWorkspace()?.id,
              let monitorId = controller.workspaceManager.monitorId(for: workspaceId)
        else {
            Issue.record("Missing workspace for same-app succession fixture")
            return nil
        }

        let pid: pid_t = 97_201
        let predecessorToken = controller.workspaceManager.addWindow(
            makeLayoutPlanTestWindow(windowId: 97_001),
            pid: pid,
            windowId: 97_001,
            to: workspaceId
        )
        let successorToken = controller.workspaceManager.addWindow(
            makeLayoutPlanTestWindow(windowId: 97_002),
            pid: pid,
            windowId: 97_002,
            to: workspaceId
        )
        #expect(controller.workspaceManager.setManagedFocus(
            predecessorToken,
            in: workspaceId,
            onMonitor: monitorId
        ))

        controller.hasStartedServices = true
        controller.axEventHandler.visibleWindowInfoProvider = { [] }
        controller.axEventHandler.focusedWindowRefProvider = { candidatePid in
            candidatePid == pid
                ? AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: successorToken.windowId)
                : nil
        }
        controller.axEventHandler.bundleIdProvider = { _ in "com.example.same-app" }
        controller.axEventHandler.windowFactsProvider = { axRef, candidatePid in
            self.standardWindowFacts(pid: candidatePid, windowId: axRef.windowId)
        }
        controller.axEventHandler.isFullscreenProvider = { _ in false }

        return SameAppSuccessionFixture(
            controller: controller,
            pid: pid,
            predecessorToken: predecessorToken,
            successorToken: successorToken
        )
    }

    private func standardWindowFacts(pid: pid_t, windowId: Int) -> WindowRuleFacts {
        WindowRuleFacts(
            appName: "Same App",
            ax: AXWindowFacts(
                role: kAXWindowRole as String,
                subrole: kAXStandardWindowSubrole as String,
                title: "Window \(windowId)",
                hasCloseButton: true,
                hasFullscreenButton: true,
                fullscreenButtonEnabled: true,
                hasZoomButton: true,
                hasMinimizeButton: true,
                appPolicy: .regular,
                bundleId: "com.example.same-app",
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

    private func enumeratedWindow(_ token: WindowToken) -> (AXWindowRef, pid_t, Int) {
        (
            AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: token.windowId),
            token.pid,
            token.windowId
        )
    }

    private func hasFocusDecision(
        _ controller: WMController,
        token: WindowToken,
        containing fragment: String
    ) -> Bool {
        controller.axEventHandler.niriCreateFocusTraceSnapshotForTests().contains { event in
            if case let .followFocusToParkedWindow(observedToken, _, decision) = event.kind {
                return observedToken == token && decision.contains(fragment)
            }
            return false
        }
    }

    private func waitUntil(
        iterations: Int = 300,
        condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0 ..< iterations {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Timed out waiting for same-app focus succession condition")
    }
}
