// SPDX-FileCopyrightText: 2026 BarutSRB
// SPDX-FileCopyrightText: 2026 Aleksei Gurianov and Nehir contributors
// SPDX-FileComment: Provenance=upstream-derived; Upstream-Project=OmniWM; Upstream-Author=BarutSRB; Nehir-Changes-Since=2026; See=NOTICE.md
//
// SPDX-License-Identifier: GPL-2.0-only

import ApplicationServices
import CoreGraphics
import Foundation

typealias SLPSMode = UInt32
let kCPSUserGenerated: SLPSMode = 0x200

@_silgen_name("_SLPSSetFrontProcessWithOptions")
func _SLPSSetFrontProcessWithOptions(
    _ psn: inout ProcessSerialNumber,
    _ wid: UInt32,
    _ mode: SLPSMode
) -> OSStatus

@_silgen_name("SLPSPostEventRecordTo")
func SLPSPostEventRecordTo(
    _ psn: inout ProcessSerialNumber,
    _ bytes: UnsafeMutablePointer<UInt8>
) -> OSStatus

@_silgen_name("GetProcessForPID")
func GetProcessForPID(_ pid: pid_t, _ psn: inout ProcessSerialNumber) -> OSStatus

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowId: inout CGWindowID) -> AXError

func getWindowId(from windowRef: AXUIElement) -> CGWindowID? {
    var windowId: CGWindowID = 0
    let result = _AXUIElementGetWindow(windowRef, &windowId)
    return result == .success ? windowId : nil
}

enum KeyWindowEventRecord {
    enum EventType: UInt8 {
        case mouseDown = 0x01
        case mouseUp = 0x02
    }

    private static let bufferSize = 0x100
    private static let declaredLength: UInt8 = 0xF8
    private static let declaredLengthOffset = 0x04
    private static let eventTypeOffset = 0x08
    private static let windowLocationOffset = 0x20
    private static let keyWindowFlagOffset = 0x3A
    private static let keyWindowFlag: UInt8 = 0x10
    private static let windowIdOffset = 0x3C
    /// A finite point outside any window's content. All-`0xFF` here decodes as
    /// NaN in both coordinates; a synthesised mouse-derived event should carry
    /// a valid position instead.
    private static let offContentLocation = CGPoint(x: -1, y: -1)

    static func make(windowId: UInt32) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: bufferSize)
        bytes[declaredLengthOffset] = declaredLength
        bytes[keyWindowFlagOffset] = keyWindowFlag
        setEventType(.mouseDown, in: &bytes)
        encode(offContentLocation, in: &bytes, at: windowLocationOffset)
        encode(windowId, in: &bytes, at: windowIdOffset)
        return bytes
    }

    static func setEventType(_ eventType: EventType, in bytes: inout [UInt8]) {
        bytes[eventTypeOffset] = eventType.rawValue
    }

    private static func encode(_ value: some Any, in bytes: inout [UInt8], at offset: Int) {
        withUnsafeBytes(of: value) { encodedValue in
            for index in encodedValue.indices {
                bytes[offset + index] = encodedValue[index]
            }
        }
    }
}

func makeKeyWindow(psn: inout ProcessSerialNumber, windowId: UInt32) {
    var eventBytes = KeyWindowEventRecord.make(windowId: windowId)
    _ = SLPSPostEventRecordTo(&psn, &eventBytes)
    KeyWindowEventRecord.setEventType(.mouseUp, in: &eventBytes)
    _ = SLPSPostEventRecordTo(&psn, &eventBytes)
}

func focusWindow(pid: pid_t, windowId: UInt32, windowRef _: AXUIElement) {
    var psn = ProcessSerialNumber()
    guard GetProcessForPID(pid, &psn) == noErr else { return }

    _ = _SLPSSetFrontProcessWithOptions(&psn, windowId, kCPSUserGenerated)
    makeKeyWindow(psn: &psn, windowId: windowId)
}
