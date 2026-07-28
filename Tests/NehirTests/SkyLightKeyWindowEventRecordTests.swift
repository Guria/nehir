// SPDX-FileCopyrightText: 2026 BarutSRB
// SPDX-FileCopyrightText: 2026 Aleksei Gurianov and Nehir contributors
// SPDX-FileComment: Provenance=upstream-derived; Upstream-Project=OmniWM; Upstream-Author=BarutSRB; Nehir-Changes-Since=2026; See=NOTICE.md
//
// SPDX-License-Identifier: GPL-2.0-only

import CoreGraphics
import Foundation
@testable import Nehir
import Testing

/// Byte-layout coverage for the synthesised SkyLight key-window event record.
///
/// The record is handed to an undocumented SkyLight entry point, so its layout
/// is a wire format with no compiler-checked contract: a wrong offset or width
/// fails silently at runtime rather than at build time. These tests pin the
/// offsets as literals on purpose — reusing the production constants would
/// assert only that the file agrees with itself.
///
/// The window-location field is the reason this file exists. It once carried
/// `0xFF` in all sixteen bytes, which decodes as NaN in both coordinates; a
/// synthesised mouse-derived event must carry a valid position instead.
struct SkyLightKeyWindowEventRecordTests {
    /// Byte offsets, restated independently of `KeyWindowEventRecord`.
    private enum Offset {
        static let declaredLength = 0x04
        static let eventType = 0x08
        static let windowLocation = 0x20
        static let keyWindowFlag = 0x3A
        static let windowId = 0x3C
    }

    private static let bufferSize = 0x100
    private static let declaredLength = 0xF8

    @Test
    func recordDeclaresItsProtocolFields() {
        let bytes = KeyWindowEventRecord.make(windowId: 1)

        #expect(bytes.count == Self.bufferSize)
        #expect(bytes[Offset.declaredLength] == UInt8(Self.declaredLength))
        #expect(bytes[Offset.keyWindowFlag] == 0x10)
    }

    @Test
    func recordStartsAsAMouseDownEvent() {
        let bytes = KeyWindowEventRecord.make(windowId: 1)

        #expect(bytes[Offset.eventType] == 0x01)
    }

    @Test
    func settingTheEventTypeRewritesOnlyThatByte() {
        var bytes = KeyWindowEventRecord.make(windowId: 0xA1B2_C3D4)
        let beforeMutation = bytes

        KeyWindowEventRecord.setEventType(.mouseUp, in: &bytes)

        #expect(bytes[Offset.eventType] == 0x02)
        let untouched = bytes.indices.filter { $0 != Offset.eventType }
        #expect(untouched.allSatisfy { bytes[$0] == beforeMutation[$0] })

        KeyWindowEventRecord.setEventType(.mouseDown, in: &bytes)
        #expect(bytes == beforeMutation)
    }

    @Test
    func recordCarriesTheWindowIdVerbatim() {
        let windowId: UInt32 = 0xA1B2_C3D4
        let bytes = KeyWindowEventRecord.make(windowId: windowId)

        var decoded: UInt32 = 0
        withUnsafeMutableBytes(of: &decoded) { destination in
            destination.copyBytes(
                from: bytes[Offset.windowId ..< Offset.windowId + MemoryLayout<UInt32>.size]
            )
        }

        #expect(decoded == windowId)
    }

    /// The regression this file is named for: the location must decode as a
    /// finite point, never NaN.
    @Test
    func windowLocationIsAFiniteOffContentPoint() {
        let bytes = KeyWindowEventRecord.make(windowId: 1)

        var decoded = CGPoint.zero
        withUnsafeMutableBytes(of: &decoded) { destination in
            destination.copyBytes(
                from: bytes[Offset.windowLocation ..< Offset.windowLocation + MemoryLayout<CGPoint>.size]
            )
        }

        #expect(!decoded.x.isNaN)
        #expect(!decoded.y.isNaN)
        #expect(decoded.x.isFinite)
        #expect(decoded.y.isFinite)
        #expect(decoded == CGPoint(x: -1, y: -1))
    }

    /// The buffer is padded past the declared payload; the padding must stay
    /// zero so the extra bytes carry no accidental meaning.
    @Test
    func bytesPastTheDeclaredLengthAreZero() {
        let bytes = KeyWindowEventRecord.make(windowId: 0xFFFF_FFFF)

        #expect(bytes[Self.declaredLength...].allSatisfy { $0 == 0 })
    }

    /// Every byte outside the four fields the record actually sets must be
    /// zero — a stray write elsewhere in the payload would be invisible
    /// otherwise.
    @Test
    func noOtherPayloadByteIsSet() {
        let bytes = KeyWindowEventRecord.make(windowId: 0xA1B2_C3D4)

        let written = Set(
            [Offset.declaredLength, Offset.eventType, Offset.keyWindowFlag]
                + Array(Offset.windowLocation ..< Offset.windowLocation + MemoryLayout<CGPoint>.size)
                + Array(Offset.windowId ..< Offset.windowId + MemoryLayout<UInt32>.size)
        )

        let strays = bytes.indices.filter { !written.contains($0) && bytes[$0] != 0 }
        #expect(strays.isEmpty, "unexpected non-zero bytes at offsets \(strays.map { String($0, radix: 16) })")
    }
}
