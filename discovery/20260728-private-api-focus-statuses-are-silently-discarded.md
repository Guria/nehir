# Private-API focus failures are silently discarded

**Verdict up front.** This is a confirmed observability gap, not a confirmed
focus bug. Every fallible SkyLight step in Nehir's key-window focus sequence
returns an `OSStatus`, but the status is either discarded or converted into a
silent early return. The caller-facing API is `Void`, so neither the focus
coordinator, runtime trace, command palette nor user can distinguish a
successful private-API focus from a failed one.

Plan a narrow Nehir-native diagnostic rather than porting upstream's 477-line
private-API health subsystem. Do not add fallback behaviour until a real failure
has been captured and its safe recovery is known.

Re-verified against Nehir `main` at `6bdd9b10` on 2026-07-28, after the
SkyLight event-record hardening shipped in PR
<https://github.com/apphane-dev/nehir/pull/187>. The hardening changed the
record layout and added byte-level tests; it deliberately preserved all ignored
statuses, so this observability gap remains open.

---

## The main focus path loses every status

`Sources/Nehir/Core/PrivateAPIs.swift:81-85` posts the synthetic mouse-down and
mouse-up records and explicitly discards both results:

```swift
_ = SLPSPostEventRecordTo(&psn, &eventBytes)
KeyWindowEventRecord.setEventType(.mouseUp, in: &eventBytes)
_ = SLPSPostEventRecordTo(&psn, &eventBytes)
```

`Sources/Nehir/Core/PrivateAPIs.swift:88-93` handles the surrounding steps in
two different but equally silent ways:

```swift
var psn = ProcessSerialNumber()
guard GetProcessForPID(pid, &psn) == noErr else { return }

_ = _SLPSSetFrontProcessWithOptions(&psn, windowId, kCPSUserGenerated)
makeKeyWindow(psn: &psn, windowId: windowId)
```

The four outcomes are therefore invisible:

1. `GetProcessForPID` can fail; the function returns with no record of why.
2. `_SLPSSetFrontProcessWithOptions` can fail; Nehir still posts both event
   records as if the front-process step succeeded.
3. The mouse-down record can fail; Nehir still mutates and posts mouse-up.
4. The mouse-up record can fail; the function returns as if the sequence
   completed.

The sequence may deliberately remain best-effort — there is no evidence yet
that aborting after one failed step is safer. The defect established here is
that Nehir cannot tell which step failed.

## The caller has no return channel

The loss is structural above `PrivateAPIs.swift`, not just two `_ =` spellings.

`Sources/Nehir/Core/Controller/WMController.swift:13-33` defines
`WindowFocusOperations.focusSpecificWindow` as a closure returning `Void`.
The live implementation at `:42-44` forwards to `Nehir.focusWindow`, also
`Void`.

`Sources/Nehir/Core/Controller/WMController.swift:4141-4150` then performs:

```swift
axEventHandler.recordSelfInitiatedFronting(pid: pid)
windowFocusOperations.activateApp(pid)
windowFocusOperations.focusSpecificWindow(pid, UInt32(windowId), axRef.element)
windowFocusOperations.raiseWindow(axRef.element)
```

So `recordSelfInitiatedFronting` is armed before any private call, and
`raiseWindow` runs after it regardless of status. The trace can report that
Nehir *requested* focus, but not whether SkyLight accepted any step.

The main managed path immediately schedules
`probeFocusedWindowAfterFronting` (`WMController.swift:4218-4224`). The probe
asks AX what is focused and can eventually observe the resulting state, but it
cannot attribute a mismatch to `GetProcessForPID`, front-process selection,
mouse-down posting or mouse-up posting because all four statuses are gone.

`FocusBridgeCoordinator.focusWindow`
(`Sources/Nehir/Core/Controller/KeyboardFocusLifecycleCoordinator.swift:214-247`)
also receives `performFocus: () -> Void`. It clears its synchronous
`isFocusOperationPending` guard immediately after invoking the closure; there
is no completion/result value to record.

## The command palette duplicates the gap and reports success

`Sources/Nehir/UI/CommandPalette/CommandPaletteController.swift:1038-1046`
directly repeats the same private-API sequence:

```swift
var psn = ProcessSerialNumber()
if GetProcessForPID(target.app.processIdentifier, &psn) == noErr {
    _ = _SLPSSetFrontProcessWithOptions(&psn, UInt32(windowId), kCPSUserGenerated)
    makeKeyWindow(psn: &psn, windowId: UInt32(windowId))
}

app.activate(options: [])
return true
```

If `GetProcessForPID` fails, the SkyLight portion is skipped silently. If any
later status fails, it is discarded. In either case the method activates the
application and returns `true`, so command execution reports success even when
the requested specific window may not have become key.

This path already owns the focused `AXUIElement`; `focusWindow`'s AX argument is
currently unused. A future implementation can eliminate the duplicate private
sequence by routing the palette through the same narrow wrapper after its
`orderWindow` call, without changing ordering semantics.

## Existing diagnostics do not cover this surface

The 2026-06-29 upstream sweep triaged commits `6bd0bf75` + `644d9115`
(`PrivateAPIHealthDiagnostics` / `FallbackFiringRecorder`) as **🟢 idea-borrow
only**, on the basis that Nehir already instruments its SkyLight surface in
`SpaceTopology` and its runtime diagnostics.

That conclusion was too broad. Nehir's diagnostics cover topology and other
specific SkyLight operations, but no source on `main` records the statuses from
`SLPSPostEventRecordTo`, `_SLPSSetFrontProcessWithOptions`, or failed
`GetProcessForPID` in the focus path. This concrete gap upgrades the concept
from a generic upstream idea to a scoped Nehir candidate.

Upstream's relevant instrumentation is small despite the surrounding large
subsystem. It assigns counters to:

- `skylight/getProcessForPIDFailed`
- `skylight/setFrontProcessFailed`
- `skylight/postEventRecordFailed`

It does not change focus decisions; it only makes failures visible. That is the
part worth adapting in Nehir's vocabulary.

## Recommended shape for a plan

Keep the first implementation observability-only:

1. Introduce a narrow result/diagnostic vocabulary for the four focus steps:
   process lookup, front-process selection, mouse-down post, mouse-up post.
   Preserve the exact raw `OSStatus`; a single merged
   `postEventRecordFailed` counter cannot tell which half of the synthetic click
   failed.
2. Record count + last status for each step, and enough context to correlate the
   event (`pid`, `windowId`, caller path if the palette remains separate).
3. Surface the snapshot in `RuntimeDiagnosticsCoordinator.runtimeStateDebugDump`
   so it lands in normal runtime-trace captures. An `OSLog` line can supplement
   the durable snapshot, but must not be the only sink: a user-provided runtime
   trace is the artifact investigations inspect.
4. Route command-palette focus through the shared wrapper, or explicitly record
   the same statuses there. Do not leave two differently instrumented versions
   of the protocol.
5. Preserve the current best-effort sequence and `Void` behaviour initially.
   Do not make a failed mouse-down suppress mouse-up, do not invent an AX
   fallback, and do not report command failure until runtime evidence establishes
   the correct policy.
6. Add tests only after the implementation's runtime capture is confirmed.
   Fake the private-API boundary with scoped operations; do not add a `ForTests`
   branch that changes the production decision path.

Likely files for the eventual plan:

- `Sources/Nehir/Core/PrivateAPIs.swift`
- a small diagnostics type under `Sources/Nehir/Core/Diagnostics/`
- `Sources/Nehir/Core/Controller/RuntimeDiagnosticsCoordinator.swift`
- `Sources/Nehir/UI/CommandPalette/CommandPaletteController.swift`
- a new per-behaviour test file after runtime confirmation

## Runtime acceptance signal

Because no private-API failure is currently reproducible, acceptance is about
truthful capture rather than fallback behaviour. Temporarily fake or force one
non-`noErr` status at the private-API boundary in an instrumented development
build, then capture a runtime trace and verify the exact step and raw status
appear in the trace artifact. Remove the forcing instrumentation before
finalisation. A production `os_log` line alone does not satisfy this check.

Only after a naturally occurring failure is captured should a separate
discovery decide whether Nehir should retry, fall back to AX, stop the synthetic
sequence, or propagate a command failure.
