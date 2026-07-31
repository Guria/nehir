// SPDX-FileCopyrightText: 2026 Aleksei Gurianov and Nehir contributors
// SPDX-FileComment: Provenance=nehir-original; See=NOTICE.md
//
// SPDX-License-Identifier: GPL-2.0-only

import ApplicationServices
import CoreGraphics
import Foundation
@testable import Nehir
import Testing

private let qutebrowserBundleId = "org.qutebrowser.qutebrowser"

@MainActor
struct QutebrowserWorkspaceBarProjectionTests {
    @Test func topLevelDialogAcceptsRawAndNormalizedUnparentedRepresentations() {
        #expect(isUserAddressableQutebrowserDialog(parentWindowId: 0))
        #expect(isUserAddressableQutebrowserDialog(parentWindowId: nil))
        #expect(WindowRuleEngine.presentsAsUserAddressableAXWindowSurface(
            bundleId: qutebrowserBundleId.uppercased(),
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String,
            windowLevel: 0,
            parentWindowId: nil
        ))
    }

    @Test func dialogExceptionDoesNotApplyToChildrenOrOtherApps() {
        #expect(!isUserAddressableQutebrowserDialog(parentWindowId: 41))
        #expect(!WindowRuleEngine.presentsAsUserAddressableAXWindowSurface(
            bundleId: "com.example.browser",
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String,
            windowLevel: 0,
            parentWindowId: nil
        ))
    }

    @Test func normalizedTopLevelDialogAppearsInFloatingWorkspaceBarProjection() {
        let controller = makeLayoutPlanTestController()
        guard let workspaceId = controller.interactionWorkspace()?.id else {
            Issue.record("Missing workspace for qutebrowser bar-projection fixture")
            return
        }

        let topLevelToken = controller.workspaceManager.addWindow(
            makeLayoutPlanTestWindow(windowId: 98_001),
            pid: 98_101,
            windowId: 98_001,
            to: workspaceId,
            mode: .floating,
            managedReplacementMetadata: qutebrowserMetadata(
                workspaceId: workspaceId,
                parentWindowId: nil
            )
        )
        let childToken = controller.workspaceManager.addWindow(
            makeLayoutPlanTestWindow(windowId: 98_002),
            pid: 98_101,
            windowId: 98_002,
            to: workspaceId,
            mode: .floating,
            managedReplacementMetadata: qutebrowserMetadata(
                workspaceId: workspaceId,
                parentWindowId: 98_001
            )
        )

        let visibleTokens = Set(
            controller.workspaceManager
                .barVisibleEntries(in: workspaceId, showFloatingWindows: true)
                .map(\.token)
        )
        #expect(visibleTokens.contains(topLevelToken))
        #expect(!visibleTokens.contains(childToken))
    }

    private func isUserAddressableQutebrowserDialog(parentWindowId: UInt32?) -> Bool {
        WindowRuleEngine.presentsAsUserAddressableAXWindowSurface(
            bundleId: qutebrowserBundleId,
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String,
            windowLevel: 0,
            parentWindowId: parentWindowId
        )
    }

    private func qutebrowserMetadata(
        workspaceId: WorkspaceDescriptor.ID,
        parentWindowId: UInt32?
    ) -> ManagedReplacementMetadata {
        ManagedReplacementMetadata(
            bundleId: qutebrowserBundleId,
            workspaceId: workspaceId,
            mode: .floating,
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String,
            title: "qutebrowser",
            windowLevel: 0,
            parentWindowId: parentWindowId,
            frame: CGRect(x: 50, y: 50, width: 800, height: 600)
        )
    }
}
