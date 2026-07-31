// SPDX-FileCopyrightText: 2026 Aleksei Gurianov and Nehir contributors
// SPDX-FileComment: Provenance=nehir-original; See=NOTICE.md
//
// SPDX-License-Identifier: GPL-2.0-only

import AppKit
import CoreGraphics
import Foundation
@testable import Nehir
import Testing

@MainActor
struct WindowServerPointerOcclusionTests {
    @Test func managedWindowStopsFrontToBackOcclusionScan() {
        let point = CGPoint(x: 120, y: 120)
        let frame = CGRect(x: 40, y: 40, width: 240, height: 180)
        let managedWindowId = 81_001
        let unmanagedWindowId = 81_002
        let managed = makeWindowInfo(
            windowId: managedWindowId,
            pid: 81_101,
            appKitFrame: frame,
            ownerName: "Managed"
        )
        let unmanaged = makeWindowInfo(
            windowId: unmanagedWindowId,
            pid: 81_102,
            appKitFrame: frame,
            ownerName: "Unmanaged"
        )

        #expect(!WMController.visibleUnmanagedInteractiveWindowServerWindowCovers(
            point: point,
            trackedWindowIds: [managedWindowId],
            windows: [managed, unmanaged]
        ))
        #expect(WMController.visibleUnmanagedInteractiveWindowServerWindowCovers(
            point: point,
            trackedWindowIds: [managedWindowId],
            windows: [unmanaged, managed]
        ))
    }

    @Test func notificationCenterBackdropRequiresSystemBundleLevelAndScreenFrame() {
        let screen = CGRect(x: 0, y: 0, width: 2_056, height: 1_329)
        let backdropLevel = Int(CGWindowLevelForKey(.dockWindow)) + 1

        #expect(WMController.isClickThroughNotificationCenterBackdrop(
            bundleIdentifier: "com.apple.notificationcenterui",
            layer: backdropLevel,
            frame: screen,
            screenFrames: [screen]
        ))
        #expect(!WMController.isClickThroughNotificationCenterBackdrop(
            bundleIdentifier: "com.apple.notificationcenterui",
            layer: backdropLevel,
            frame: CGRect(x: 1_600, y: 900, width: 360, height: 360),
            screenFrames: [screen]
        ))
        #expect(!WMController.isClickThroughNotificationCenterBackdrop(
            bundleIdentifier: "com.example.overlay",
            layer: backdropLevel,
            frame: screen,
            screenFrames: [screen]
        ))
        #expect(!WMController.isClickThroughNotificationCenterBackdrop(
            bundleIdentifier: "com.apple.notificationcenterui",
            layer: Int(CGWindowLevelForKey(.dockWindow)),
            frame: screen,
            screenFrames: [screen]
        ))
        #expect(!WMController.isClickThroughNotificationCenterBackdrop(
            bundleIdentifier: "com.apple.notificationcenterui",
            layer: Int(CGWindowLevelForKey(.mainMenuWindow)),
            frame: screen,
            screenFrames: [screen]
        ))
    }

    @Test func notificationCenterBackdropMaySpanTheVirtualScreen() {
        let left = CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080)
        let right = CGRect(x: 0, y: 0, width: 2_056, height: 1_329)
        let virtualScreen = left.union(right)

        #expect(WMController.isClickThroughNotificationCenterBackdrop(
            bundleIdentifier: "com.apple.notificationcenterui",
            layer: Int(CGWindowLevelForKey(.dockWindow)) + 1,
            frame: virtualScreen,
            screenFrames: [left, right]
        ))
    }

    @Test func directPointerPathUsesInjectedOwnerBundleLookup() throws {
        let screen = try #require(NSScreen.main?.frame)
        let controller = makeLayoutPlanTestController()
        let windowId = 81_003
        let ownerPid: pid_t = 81_103
        controller.unmanagedWindowServerWindowOwnerProvider = { candidateWindowId in
            candidateWindowId == windowId
                ? (pid: ownerPid, ownerName: "System Overlay")
                : nil
        }
        controller.ownerBundleIdProvider = { candidatePid in
            candidatePid == ownerPid ? "com.apple.notificationcenterui" : nil
        }
        controller.unmanagedOverlayWindowInfoProvider = {
            [self.makeWindowInfo(
                windowId: windowId,
                pid: ownerPid,
                appKitFrame: screen,
                layer: Int(CGWindowLevelForKey(.dockWindow)) + 1,
                ownerName: "System Overlay"
            )]
        }

        #expect(!controller.unmanagedInteractiveWindowServerWindowCovers(
            point: screen.center,
            windowUnderPointer: windowId,
            allowWindowServerSnapshotFallback: false
        ))
    }

    private func makeWindowInfo(
        windowId: Int,
        pid: pid_t,
        appKitFrame: CGRect,
        layer: Int = 0,
        ownerName: String
    ) -> [String: Any] {
        let quartz = ScreenCoordinateSpace.toWindowServer(rect: appKitFrame)
        return [
            kCGWindowNumber as String: NSNumber(value: windowId),
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowOwnerName as String: ownerName,
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowIsOnscreen as String: NSNumber(value: true),
            kCGWindowBounds as String: [
                "X": NSNumber(value: Double(quartz.minX)),
                "Y": NSNumber(value: Double(quartz.minY)),
                "Width": NSNumber(value: Double(quartz.width)),
                "Height": NSNumber(value: Double(quartz.height))
            ]
        ]
    }
}
