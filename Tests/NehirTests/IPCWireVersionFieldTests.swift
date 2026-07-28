// SPDX-FileCopyrightText: 2026 Aleksei Gurianov and Nehir contributors
// SPDX-FileComment: Provenance=nehir-original; See=NOTICE.md
//
// SPDX-License-Identifier: GPL-2.0-only

import Foundation
import NehirIPC
import Testing

private func encodedKeys(_ data: Data) throws -> Set<String> {
    let object = try #require(
        JSONSerialization.jsonObject(with: Data(data.dropLast())) as? [String: Any]
    )
    return Set(object.keys)
}

@Suite struct IPCWireVersionFieldTests {
    @Test func requestResponseAndEventEnvelopesOmitProtocolVersion() throws {
        let request = IPCRequest(
            id: "req-1",
            command: .focus(direction: .left),
            authorizationToken: "secret-token"
        )
        let response = IPCResponse.success(
            id: "req-1",
            kind: .command,
            result: IPCResult(apps: IPCAppsQueryResult(apps: []))
        )
        let event = IPCEventEnvelope.success(
            id: "evt-1",
            channel: .focus,
            result: IPCResult(focusedWindow: IPCFocusedWindowQueryResult(window: nil))
        )

        let requestKeys = try encodedKeys(IPCWire.encodeRequestLine(request))
        let responseKeys = try encodedKeys(IPCWire.encodeResponseLine(response))
        let eventKeys = try encodedKeys(IPCWire.encodeEventLine(event))

        #expect(requestKeys.contains("id"))
        #expect(!requestKeys.contains("version"))
        #expect(!responseKeys.contains("version"))
        #expect(!eventKeys.contains("version"))
    }

    @Test func versionAndCapabilitiesResultsOmitProtocolVersion() throws {
        let encoder = IPCWire.makeEncoder()
        let version = try encoder.encode(IPCVersionResult(appVersion: "1.2.3"))
        let capabilities = try encoder.encode(
            IPCCapabilitiesQueryResult(
                appVersion: "1.2.3",
                authorizationRequired: true,
                windowIdScope: "session",
                queries: [],
                commands: [],
                ruleActions: [],
                workspaceActions: [],
                windowActions: [],
                subscriptions: []
            )
        )

        let versionObject = try #require(
            JSONSerialization.jsonObject(with: version) as? [String: Any]
        )
        let capabilitiesObject = try #require(
            JSONSerialization.jsonObject(with: capabilities) as? [String: Any]
        )

        #expect(versionObject["appVersion"] as? String == "1.2.3")
        #expect(versionObject["protocolVersion"] == nil)
        #expect(capabilitiesObject["appVersion"] as? String == "1.2.3")
        #expect(capabilitiesObject["protocolVersion"] == nil)
    }
}
