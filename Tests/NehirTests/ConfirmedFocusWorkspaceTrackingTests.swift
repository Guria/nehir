// SPDX-FileCopyrightText: 2026 Aleksei Gurianov and Nehir contributors
// SPDX-FileComment: Provenance=nehir-original; See=NOTICE.md
//
// SPDX-License-Identifier: GPL-2.0-only

import AppKit
@testable import Nehir
import Testing

private func makeConfirmedFocusTestDefaults() -> UserDefaults {
    let suiteName = "dev.guria.nehir.confirmed-focus-workspace.test.\(UUID().uuidString)"
    return UserDefaults(suiteName: suiteName)!
}

private func makeConfirmedFocusTestMonitor(
    displayId: CGDirectDisplayID,
    name: String,
    x: CGFloat
) -> Monitor {
    let frame = CGRect(x: x, y: 0, width: 1920, height: 1080)
    return Monitor(
        id: Monitor.ID(displayId: displayId),
        displayId: displayId,
        frame: frame,
        visibleFrame: frame,
        hasNotch: false,
        name: name
    )
}

@MainActor
private func addConfirmedFocusTestHandle(
    manager: WorkspaceManager,
    windowId: Int,
    workspaceId: WorkspaceDescriptor.ID
) -> WindowHandle {
    let token = manager.addWindow(
        AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: windowId),
        pid: getpid(),
        windowId: windowId,
        to: workspaceId
    )
    guard let handle = manager.handle(for: token) else {
        fatalError("Expected bridge handle for confirmed-focus workspace test")
    }
    return handle
}

/// The confirmed managed focus records *where* it was confirmed, not just which
/// window.
///
/// The AX focus-confirmation path preserves the destination viewport when it sees a
/// re-confirmation of the already-confirmed focus token, so that a quick-terminal
/// hide re-focusing the existing window does not scroll the viewport back to a
/// column the user deliberately scrolled away from. Deciding that on the token
/// alone cannot tell such a re-focus apart from the same window being re-focused
/// after moving to a different workspace — where the window's column is wherever
/// the transfer appended it, so preserving the viewport leaves it parked offscreen
/// while holding focus.
///
/// The workspace therefore has to survive the reconcile cycle: confirmations arrive
/// through `confirmManagedFocus`, whose focus-session write is replaced wholesale
/// from a `FocusSessionSnapshot`. A value recorded only on the live session state is
/// overwritten on the next reconcile.
@Suite @MainActor struct ConfirmedFocusWorkspaceTrackingTests {
    private struct Fixture {
        let manager: WorkspaceManager
        let workspaceOne: WorkspaceDescriptor.ID
        let workspaceTwo: WorkspaceDescriptor.ID
        let monitor: Monitor
    }

    /// Two workspaces on one monitor, matching the topology the bug was reported on.
    private func makeFixture() -> Fixture {
        let settings = SettingsStore(defaults: makeConfirmedFocusTestDefaults())
        settings.workspaceConfigurations = [
            WorkspaceConfiguration(name: "1", monitorAssignment: .main),
            WorkspaceConfiguration(name: "2", monitorAssignment: .main)
        ]

        let manager = WorkspaceManager(settings: settings)
        let monitor = makeConfirmedFocusTestMonitor(displayId: 10, name: "Main", x: 0)
        manager.applyMonitorConfigurationChange([monitor])

        guard let workspaceOne = manager.workspaceId(for: "1", createIfMissing: true),
              let workspaceTwo = manager.workspaceId(for: "2", createIfMissing: true)
        else {
            fatalError("Expected both test workspaces")
        }

        return Fixture(
            manager: manager,
            workspaceOne: workspaceOne,
            workspaceTwo: workspaceTwo,
            monitor: monitor
        )
    }

    @discardableResult
    private func confirm(
        _ handle: WindowHandle,
        in workspaceId: WorkspaceDescriptor.ID,
        fixture: Fixture
    ) -> Bool {
        fixture.manager.confirmManagedFocus(
            handle,
            in: workspaceId,
            onMonitor: fixture.monitor.id,
            appFullscreen: false,
            activateWorkspaceOnMonitor: true
        )
    }

    @Test func confirmingFocusRecordsTheWorkspaceItWasConfirmedIn() {
        let fixture = makeFixture()
        let handle = addConfirmedFocusTestHandle(
            manager: fixture.manager,
            windowId: 3101,
            workspaceId: fixture.workspaceOne
        )

        confirm(handle, in: fixture.workspaceOne, fixture: fixture)

        #expect(fixture.manager.confirmedManagedFocusToken == handle.id)
        #expect(fixture.manager.confirmedManagedFocusWorkspaceId == fixture.workspaceOne)
    }

    /// The case the reported bug turned on: the same window is re-confirmed after
    /// being reassigned to another workspace, so the recorded workspace must move
    /// with it. A stale value would make the re-confirmation look like a re-focus in
    /// place and suppress the reveal.
    @Test func reconfirmingTheSameWindowInAnotherWorkspaceUpdatesTheRecordedWorkspace() {
        let fixture = makeFixture()
        let handle = addConfirmedFocusTestHandle(
            manager: fixture.manager,
            windowId: 3102,
            workspaceId: fixture.workspaceOne
        )

        confirm(handle, in: fixture.workspaceOne, fixture: fixture)
        #expect(fixture.manager.confirmedManagedFocusWorkspaceId == fixture.workspaceOne)

        fixture.manager.setWorkspace(for: handle.id, to: fixture.workspaceTwo)
        confirm(handle, in: fixture.workspaceTwo, fixture: fixture)

        #expect(fixture.manager.confirmedManagedFocusToken == handle.id)
        #expect(fixture.manager.confirmedManagedFocusWorkspaceId == fixture.workspaceTwo)
    }

    /// Re-confirming in the same workspace leaves the record alone, which is what
    /// keeps the quick-terminal viewport-preservation behaviour intact.
    @Test func reconfirmingInTheSameWorkspaceKeepsTheRecordedWorkspace() {
        let fixture = makeFixture()
        let handle = addConfirmedFocusTestHandle(
            manager: fixture.manager,
            windowId: 3103,
            workspaceId: fixture.workspaceOne
        )

        confirm(handle, in: fixture.workspaceOne, fixture: fixture)
        confirm(handle, in: fixture.workspaceOne, fixture: fixture)

        #expect(fixture.manager.confirmedManagedFocusWorkspaceId == fixture.workspaceOne)
    }

    /// The recorded workspace must survive a reconcile pass. `confirmManagedFocus`
    /// routes through the reducer and `applyReconciledFocusSession` replaces the
    /// focus session from a snapshot, so a field the snapshot does not carry is
    /// silently reset — which is exactly what made an earlier attempt at this fix
    /// inert.
    @Test func recordedWorkspaceSurvivesFurtherFocusSessionWrites() {
        let fixture = makeFixture()
        let first = addConfirmedFocusTestHandle(
            manager: fixture.manager,
            windowId: 3104,
            workspaceId: fixture.workspaceOne
        )
        let second = addConfirmedFocusTestHandle(
            manager: fixture.manager,
            windowId: 3105,
            workspaceId: fixture.workspaceTwo
        )

        confirm(first, in: fixture.workspaceOne, fixture: fixture)
        confirm(second, in: fixture.workspaceTwo, fixture: fixture)

        #expect(fixture.manager.confirmedManagedFocusToken == second.id)
        #expect(fixture.manager.confirmedManagedFocusWorkspaceId == fixture.workspaceTwo)

        // And back again, so the field is not merely sticky in one direction.
        confirm(first, in: fixture.workspaceOne, fixture: fixture)

        #expect(fixture.manager.confirmedManagedFocusToken == first.id)
        #expect(fixture.manager.confirmedManagedFocusWorkspaceId == fixture.workspaceOne)
    }
}
