// SPDX-FileCopyrightText: 2026 Aleksei Gurianov and Nehir contributors
// SPDX-FileComment: Provenance=nehir-original; See=NOTICE.md
//
// SPDX-License-Identifier: GPL-2.0-only

import CoreGraphics
import Foundation
@testable import Nehir
import Testing

/// Regression coverage for the quantization-refusal streak: a shrink refusal
/// whose overshoot stays within the 32 pt cell-quantization threshold is
/// absorbed as grid-snapping, but when the observed size stays frozen across
/// three consecutive attempts the window is refusing outright — a hard app
/// minimum that must be learned so the canonical layout stops overlapping the
/// neighboring column (the Helium 717 px case).
@MainActor
@Suite
struct QuantizationRefusalStreakTests {
    private func shrinkRefusalResult(
        pid: pid_t,
        windowId: Int,
        targetWidth: CGFloat,
        observedWidth: CGFloat
    ) -> AXFrameApplyResult {
        let targetFrame = CGRect(x: 0, y: 0, width: targetWidth, height: 500)
        let observedFrame = CGRect(x: 0, y: 0, width: observedWidth, height: 500)
        return AXFrameApplyResult(
            requestId: 0,
            pid: pid,
            windowId: windowId,
            targetFrame: targetFrame,
            currentFrameHint: nil,
            writeResult: AXFrameWriteResult(
                targetFrame: targetFrame,
                observedFrame: observedFrame,
                writeOrder: AXWindowService.frameWriteOrder(
                    currentFrame: nil,
                    targetFrame: targetFrame
                ),
                sizeError: .success,
                positionError: .success,
                failureReason: .verificationMismatch
            )
        )
    }

    /// A frozen observed size across three quantization-classified shrink
    /// refusals escalates to the inferred-minimum learner. The first two
    /// attempts are still absorbed as quantization.
    @Test func frozenObservedSizeEscalatesToInferredMinimumOnThirdRefusal() throws {
        let controller = makeLayoutPlanTestController()
        guard let monitor = controller.workspaceManager.monitors.first,
              let workspaceId = controller.workspaceManager.activeWorkspaceOrFirst(on: monitor.id)?.id
        else {
            Issue.record("Missing workspace for streak-escalation test")
            return
        }

        let windowId = 5401
        let token = addLayoutPlanTestWindow(on: controller, workspaceId: workspaceId, windowId: windowId)
        #expect(controller.workspaceManager.inferredResizeMinimumSize(for: token) == nil)

        // Helium shape: target 706, window pinned at 717 — an 11 pt overshoot
        // inside the quantization threshold, identical on every attempt.
        for attempt in 1 ... 2 {
            let result = shrinkRefusalResult(
                pid: token.pid,
                windowId: windowId,
                targetWidth: 706,
                observedWidth: 717
            )
            controller.layoutRefreshController.handleResizeMinimumFrameApplyResult(result, workspaceId: workspaceId)
            #expect(
                controller.workspaceManager.inferredResizeMinimumSize(for: token) == nil,
                "attempt \(attempt) must still be absorbed as quantization"
            )
        }

        let third = shrinkRefusalResult(
            pid: token.pid,
            windowId: windowId,
            targetWidth: 706,
            observedWidth: 717
        )
        controller.layoutRefreshController.handleResizeMinimumFrameApplyResult(third, workspaceId: workspaceId)

        let pinned = try #require(controller.workspaceManager.inferredResizeMinimumSize(for: token))
        #expect(pinned.width >= 717)
    }

    /// A genuine cell-quantizing app snaps to different grid lines as the
    /// target changes; a changing observed size resets the streak and never
    /// escalates, no matter how many attempts are made.
    @Test func changingObservedSizesNeverEscalate() {
        let controller = makeLayoutPlanTestController()
        guard let monitor = controller.workspaceManager.monitors.first,
              let workspaceId = controller.workspaceManager.activeWorkspaceOrFirst(on: monitor.id)?.id
        else {
            Issue.record("Missing workspace for streak-reset test")
            return
        }

        let windowId = 5402
        let token = addLayoutPlanTestWindow(on: controller, workspaceId: workspaceId, windowId: windowId)

        // Grid walk: each attempt snaps to a different nearby cell boundary.
        let attempts: [(target: CGFloat, observed: CGFloat)] = [
            (706, 717), (706, 728), (706, 717), (706, 728), (706, 717), (706, 728)
        ]
        for (index, attempt) in attempts.enumerated() {
            let result = shrinkRefusalResult(
                pid: token.pid,
                windowId: windowId,
                targetWidth: attempt.target,
                observedWidth: attempt.observed
            )
            controller.layoutRefreshController.handleResizeMinimumFrameApplyResult(result, workspaceId: workspaceId)
            #expect(
                controller.workspaceManager.inferredResizeMinimumSize(for: token) == nil,
                "attempt \(index + 1) with changing observed size must not escalate"
            )
        }
    }

    /// A successful write between refusals resets the streak: the window did
    /// resize, so the earlier refusals were transient, not a hard minimum.
    @Test func confirmedWriteBetweenRefusalsResetsStreak() {
        let controller = makeLayoutPlanTestController()
        guard let monitor = controller.workspaceManager.monitors.first,
              let workspaceId = controller.workspaceManager.activeWorkspaceOrFirst(on: monitor.id)?.id
        else {
            Issue.record("Missing workspace for streak-confirm-reset test")
            return
        }

        let windowId = 5403
        let token = addLayoutPlanTestWindow(on: controller, workspaceId: workspaceId, windowId: windowId)

        for _ in 1 ... 2 {
            let result = shrinkRefusalResult(
                pid: token.pid,
                windowId: windowId,
                targetWidth: 706,
                observedWidth: 717
            )
            controller.layoutRefreshController.handleResizeMinimumFrameApplyResult(result, workspaceId: workspaceId)
        }
        #expect(controller.workspaceManager.inferredResizeMinimumSize(for: token) == nil)

        // A confirmed write proves the window can resize; the streak restarts.
        let confirmedFrame = CGRect(x: 0, y: 0, width: 800, height: 500)
        let confirmed = AXFrameApplyResult(
            requestId: 0,
            pid: token.pid,
            windowId: windowId,
            targetFrame: confirmedFrame,
            currentFrameHint: nil,
            writeResult: AXFrameWriteResult(
                targetFrame: confirmedFrame,
                observedFrame: confirmedFrame,
                writeOrder: AXWindowService.frameWriteOrder(
                    currentFrame: nil,
                    targetFrame: confirmedFrame
                ),
                sizeError: .success,
                positionError: .success,
                failureReason: nil
            )
        )
        controller.layoutRefreshController.handleResizeMinimumFrameApplyResult(confirmed, workspaceId: workspaceId)

        // Two more refusals stay under the threshold after the reset.
        for _ in 1 ... 2 {
            let result = shrinkRefusalResult(
                pid: token.pid,
                windowId: windowId,
                targetWidth: 706,
                observedWidth: 717
            )
            controller.layoutRefreshController.handleResizeMinimumFrameApplyResult(result, workspaceId: workspaceId)
        }
        #expect(controller.workspaceManager.inferredResizeMinimumSize(for: token) == nil)
    }
}
