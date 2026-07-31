// SPDX-FileCopyrightText: 2026 Aleksei Gurianov and Nehir contributors
// SPDX-FileComment: Provenance=nehir-original; See=NOTICE.md
//
// SPDX-License-Identifier: GPL-2.0-only

import ApplicationServices
import CoreGraphics
import Foundation
@testable import Nehir
import Testing

/// Regression coverage for the quick-terminal close stealing the focus,
/// layout selection and command target of the window created during the
/// overlay session.
///
/// Ghostty's quick terminal captures the frontmost application when it opens
/// and re-activates it when it hides, ahead of the system default — it has no
/// way to know a regular window was created meanwhile. That activation is
/// genuinely external and per-event indistinguishable from a real click or
/// Cmd-Tab, so it is corrected at the overlay window's destroy instead of
/// being gated on arrival.
@MainActor
struct QuickTerminalCloseAnchorTests {
    private struct Fixture {
        let controller: WMController
        let workspaceId: WorkspaceDescriptor.ID
        let overlayPid: pid_t
        let overlayWindowId: Int
        /// The window the user created from the quick terminal.
        let userToken: WindowToken
        /// Another window of the same app, so assertions must distinguish
        /// windows rather than merely processes.
        let siblingToken: WindowToken
        let neighborToken: WindowToken
        let fronted: FrontedWindows
    }

    private final class OverlayWindowState: @unchecked Sendable {
        var isPresent = true
        var isOrderedIn = true
    }

    private struct CrossAppFixture {
        let controller: WMController
        let overlayPid: pid_t
        let overlayWindowId: Int
        let targetEntry: WindowModel.Entry
        let overlayState: OverlayWindowState

        @MainActor
        func tearDown() {
            controller.axEventHandler.windowInfoProviderIsAuthoritativeForTests = false
            controller.axEventHandler.windowInfoProvider = nil
            controller.axEventHandler.windowOrderedInProvider = nil
            controller.axEventHandler.resetDebugStateForTests()
        }
    }

    /// Records the windows Nehir fronted, in order. Window-level granularity
    /// matters: the defect is about *which* window of an app ends up focused,
    /// so a pid alone cannot tell a pass from a failure.
    private final class FrontedWindows: @unchecked Sendable {
        private(set) var tokens: [WindowToken] = []
        private(set) var activatedPids: [pid_t] = []

        func recordActivation(_ pid: pid_t) {
            activatedPids.append(pid)
        }

        func recordWindow(pid: pid_t, windowId: UInt32) {
            tokens.append(WindowToken(pid: pid, windowId: Int(windowId)))
        }

        func reset() {
            tokens.removeAll()
            activatedPids.removeAll()
        }
    }

    private func makeFixture() -> Fixture? {
        let fronted = FrontedWindows()
        let controller = makeLayoutPlanTestController(
            windowFocusOperations: WindowFocusOperations(
                activateApp: { pid in fronted.recordActivation(pid) },
                focusSpecificWindow: { pid, windowId, _ in
                    fronted.recordWindow(pid: pid, windowId: windowId)
                },
                raiseWindow: { _ in }
            )
        )
        guard let workspaceId = controller.interactionWorkspace()?.id,
              let monitorId = controller.workspaceManager.monitorId(for: workspaceId)
        else {
            Issue.record("Missing active workspace for quick-terminal fixture")
            return nil
        }

        let overlayPid: pid_t = 9_101
        let neighborPid: pid_t = 9_102
        let overlayWindowId = 9_001

        // Two windows of the overlay's app — the one the user created from
        // the quick terminal and an older sibling — plus a neighbouring app's
        // window. The sibling is what makes the assertions meaningful: both
        // candidates share a pid, so only the window identity distinguishes a
        // correct recovery from a wrong one.
        let siblingToken = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 9_004),
            pid: overlayPid,
            windowId: 9_004,
            to: workspaceId
        )
        let userToken = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 9_002),
            pid: overlayPid,
            windowId: 9_002,
            to: workspaceId
        )
        let neighborToken = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 9_003),
            pid: neighborPid,
            windowId: 9_003,
            to: workspaceId
        )
        _ = controller.workspaceManager.setManagedFocus(userToken, in: workspaceId, onMonitor: monitorId)

        // The rule engine recognizing the overlay is what arms both the
        // overlay-capable pid and the window id whose destroy means teardown.
        controller.axEventHandler.armOverlayCapabilityIfNeeded(
            source: .builtInRule("ghosttyQuickTerminalOverlay"),
            token: WindowToken(pid: overlayPid, windowId: overlayWindowId),
            facts: makeQuickTerminalFactsForTests(pid: overlayPid, windowId: overlayWindowId)
        )

        return Fixture(
            controller: controller,
            workspaceId: workspaceId,
            overlayPid: overlayPid,
            overlayWindowId: overlayWindowId,
            userToken: userToken,
            siblingToken: siblingToken,
            neighborToken: neighborToken,
            fronted: fronted
        )
    }

    private func makeCrossAppFixture() -> CrossAppFixture? {
        let controller = makeLayoutPlanTestController()
        guard let sourceWorkspaceId = controller.interactionWorkspace()?.id,
              let targetWorkspaceId = controller.workspaceManager.workspaceId(for: "2", createIfMissing: false),
              let monitorId = controller.workspaceManager.monitorId(for: sourceWorkspaceId)
        else {
            Issue.record("Missing cross-app quick-terminal workspace fixture")
            return nil
        }

        let overlayPid: pid_t = 9_201
        let targetPid: pid_t = 9_202
        let overlayWindowId = 9_211
        let sourceToken = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 9_212),
            pid: overlayPid,
            windowId: 9_212,
            to: sourceWorkspaceId
        )
        let targetToken = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 9_213),
            pid: targetPid,
            windowId: 9_213,
            to: targetWorkspaceId
        )
        guard let targetEntry = controller.workspaceManager.entry(for: targetToken) else {
            Issue.record("Missing cross-app quick-terminal target entry")
            return nil
        }
        #expect(controller.workspaceManager.setManagedFocus(
            sourceToken,
            in: sourceWorkspaceId,
            onMonitor: monitorId
        ))

        let facts = makeQuickTerminalFactsForTests(pid: overlayPid, windowId: overlayWindowId)
        controller.axEventHandler.armOverlayCapabilityIfNeeded(
            source: .builtInRule("ghosttyQuickTerminalOverlay"),
            token: WindowToken(pid: overlayPid, windowId: overlayWindowId),
            facts: facts
        )

        let overlayState = OverlayWindowState()
        controller.axEventHandler.windowInfoProviderIsAuthoritativeForTests = true
        controller.axEventHandler.windowInfoProvider = { windowId in
            guard overlayState.isPresent,
                  windowId == UInt32(overlayWindowId)
            else {
                return nil
            }
            return facts.windowServer
        }
        controller.axEventHandler.windowOrderedInProvider = { windowId in
            windowId == UInt32(overlayWindowId) ? overlayState.isOrderedIn : nil
        }

        return CrossAppFixture(
            controller: controller,
            overlayPid: overlayPid,
            overlayWindowId: overlayWindowId,
            targetEntry: targetEntry,
            overlayState: overlayState
        )
    }

    /// Confirms `token` the way an explicitly requested focus does: through a
    /// window-level activation, which is authoritative.
    private func confirmExplicitly(_ fx: Fixture, _ token: WindowToken) {
        guard let entry = fx.controller.workspaceManager.entry(for: token) else {
            Issue.record("Missing entry for \(token)")
            return
        }
        fx.controller.axEventHandler.handleManagedAppActivation(
            entry: entry,
            isWorkspaceActive: true,
            appFullscreen: false,
            source: .focusedWindowChanged
        )
    }

    /// The shape of the overlay owner's own "restore the previous app" call:
    /// an app-level activation with no matching managed request.
    private func confirmCauselessly(_ fx: Fixture, _ token: WindowToken) {
        guard let entry = fx.controller.workspaceManager.entry(for: token) else {
            Issue.record("Missing entry for \(token)")
            return
        }
        fx.controller.axEventHandler.handleManagedAppActivation(
            entry: entry,
            isWorkspaceActive: true,
            appFullscreen: false,
            source: .workspaceDidActivateApplication
        )
    }

    @Test func overlayCloseReAssertsTheWindowCreatedDuringTheSession() {
        guard let fx = makeFixture() else { return }

        // The user worked in an older window of the app, then created a new
        // one from the quick terminal: the newer explicit confirmation is the
        // anchor.
        confirmExplicitly(fx, fx.siblingToken)
        confirmExplicitly(fx, fx.userToken)
        // The overlay owner restores the pre-overlay app before its window's
        // destroy notification arrives.
        confirmCauselessly(fx, fx.neighborToken)
        #expect(fx.controller.workspaceManager.confirmedManagedFocusToken == fx.neighborToken)

        fx.fronted.reset()
        fx.controller.axEventHandler.handleRemoved(pid: fx.overlayPid, winId: fx.overlayWindowId)

        // Window-level: the app's *other* window must not be the one restored.
        // The confirmed token only changes once macOS echoes the activation
        // back, which no fake produces, so Nehir's intent is asserted through
        // the window it fronted and the request it opened.
        #expect(fx.fronted.tokens == [fx.userToken])
        #expect(fx.controller.workspaceManager.activeFocusRequestToken == fx.userToken)
    }

    /// With nothing created during the session the explicit stamp is the
    /// preserved pre-overlay token, so closing the overlay changes nothing.
    @Test func overlayCloseIsANoOpWhenNoWindowWasCreated() {
        guard let fx = makeFixture() else { return }

        confirmExplicitly(fx, fx.neighborToken)
        #expect(fx.controller.workspaceManager.confirmedManagedFocusToken == fx.neighborToken)

        fx.fronted.reset()
        fx.controller.axEventHandler.handleRemoved(pid: fx.overlayPid, winId: fx.overlayWindowId)

        #expect(fx.controller.workspaceManager.confirmedManagedFocusToken == fx.neighborToken)
        #expect(fx.fronted.tokens.isEmpty)
        #expect(fx.fronted.activatedPids.isEmpty)
    }

    /// Destroying some other untracked element of the overlay's app is not an
    /// overlay teardown and must not move focus — the assertion is keyed on
    /// the recognized overlay window's identity, not on the pid.
    @Test func destroyingAnUnrelatedWindowOfTheOverlayAppDoesNotReAssert() {
        guard let fx = makeFixture() else { return }

        confirmExplicitly(fx, fx.userToken)
        confirmCauselessly(fx, fx.neighborToken)

        fx.fronted.reset()
        fx.controller.axEventHandler.handleRemoved(pid: fx.overlayPid, winId: 9_999)

        #expect(fx.fronted.tokens.isEmpty)
        #expect(fx.controller.workspaceManager.confirmedManagedFocusToken == fx.neighborToken)
    }

    @Test func automaticCrossAppRestoreIsSuppressedWhileOverlayIsStillOrderedIn() {
        guard let fx = makeCrossAppFixture() else { return }
        defer { fx.tearDown() }

        fx.controller.axEventHandler.handleManagedAppActivation(
            entry: fx.targetEntry,
            isWorkspaceActive: false,
            appFullscreen: false,
            source: .workspaceDidActivateApplication
        )

        #expect(fx.controller.axEventHandler.niriCreateFocusTraceSnapshotForTests().contains { event in
            if case let .followFocusToParkedWindow(token, workspaceId, decision) = event.kind {
                return token == fx.targetEntry.token &&
                    workspaceId == fx.targetEntry.workspaceId &&
                    decision == "skip reason=causeless_external_overlay_close"
            }
            return false
        })
    }

    @Test func crossAppActivationFollowsParkedWindowImmediatelyAfterOverlayDestroy() {
        guard let fx = makeCrossAppFixture() else { return }
        defer { fx.tearDown() }

        fx.overlayState.isOrderedIn = false
        fx.overlayState.isPresent = false
        fx.controller.axEventHandler.handleRemoved(
            pid: fx.overlayPid,
            winId: fx.overlayWindowId
        )
        fx.controller.axEventHandler.handleManagedAppActivation(
            entry: fx.targetEntry,
            isWorkspaceActive: false,
            appFullscreen: false,
            source: .workspaceDidActivateApplication
        )

        let trace = fx.controller.axEventHandler.niriCreateFocusTraceSnapshotForTests()
        #expect(trace.contains { event in
            if case let .followFocusToParkedWindow(token, workspaceId, decision) = event.kind {
                return token == fx.targetEntry.token &&
                    workspaceId == fx.targetEntry.workspaceId &&
                    decision == "switch"
            }
            return false
        })
        #expect(!trace.contains { event in
            if case let .followFocusToParkedWindow(token, _, decision) = event.kind {
                return token == fx.targetEntry.token &&
                    decision == "skip reason=causeless_external_overlay_close"
            }
            return false
        })
    }
}
