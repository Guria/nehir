---
"nehir": minor

---

Remove the IPC protocol version field and document the IPC surface as unstable

**Breaking change for IPC clients.** The `version` field is gone from IPC requests, responses, and event envelopes, and the `protocolVersion` field is gone from the `version` command and the `capabilities` query. The server no longer rejects requests over a version mismatch, so the `protocol_mismatch` error code is removed too. The number never changed as the protocol grew, so it could not tell a client anything useful.

The IPC protocol and `nehirctl` output format are documented as unstable: they can change in any release. Integrations should key on the Nehir app version, still reported as `appVersion` by `nehirctl version` and the `capabilities` query.
