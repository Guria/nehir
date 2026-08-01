# Ghostty tab switches: the deferred destroy bypasses the managed-replacement burst, so every tab switch destroys and re-inserts the column

**Status:** completed — shipped on `main` in `acbebfbd` ("Carry window identity through tab churn and steady the overlay-close focus"), `ca152b28` ("Stabilize focus arbitration around overlays and window teardown"), and `b0bca2f6` ("Harden overlay lifecycle and focus recovery"), merged 2026-07-31 via PR #193, contained in `v0.6.0-rc.43`. The user confirmed Ghostty tab switch/create/close behavior before merge. Moved from `discovery/` to `completed/` on 2026-08-01.

**Nehir issue:** #191 ("Ghostty window shrinks to half screen when using Quick
Terminal with multiple tabs"), closed automatically when PR #193 merged on
2026-07-31. The capture baseline was `main` at `eb451326`.

Related documents:

- [`../planned/20260625-vscode-focused-admission-skips-managed-replacement-rekey.md`](../planned/20260625-vscode-focused-admission-skips-managed-replacement-rekey.md)
  — the *create* side of the same correlation mechanism. That plan is about an
  admission route that does not consult the rekey gate. This document is about
  the *destroy* side never reaching the burst at all. The two are independent
  gaps in one mechanism.
- [`20260707-final-destroy-liveness-dual-oracle.md`](20260707-final-destroy-liveness-dual-oracle.md)
  — introduced the dual-oracle deferred destroy verification.
- [`20260708-cold-start-destroy-only-replacement-bursts-click-readmit.md`](20260708-cold-start-destroy-only-replacement-bursts-click-readmit.md)
  — shipped as `a55b4e33` ("Keep live windows through CGS space churn"), which
  routed CGS `spaceWindowDestroyed` through the same deferred liveness path.
  `a55b4e33` is an ancestor of `main` at `eb451326`.

## Landed state

The deferred destroy-liveness verifier now terminates through
`finishVerifiedDestroyRemoval`, which rebuilds a prepared destroy and applies
the same `shouldDelayManagedReplacementDestroy` →
`enqueueManagedReplacementDestroy` funnel as synchronous teardown. A matching
create therefore rekeys the existing managed entry instead of removing and
re-inserting its layout column.

The merged range went beyond this discovery's one-path proposal:

- pairing is greedy and sequence ordered, so one burst can complete several
  compatible destroy/create pairs;
- one-sided bursts wait while the corresponding create materialization or
  destroy verification is still in flight;
- a per-pid liveness audit finds tracked windows whose destroy notification was
  dropped;
- teardown keeps are bounded and converge rather than rescheduling forever;
- tests assert column/focus reconciliation and the absence of pending create
  retries at the correlation boundary.

The user confirmed that switching, creating, and closing Ghostty tabs preserves
column identity and width and no longer accumulates phantom columns requiring a
restart. Rapid tab bursts may still show a brief transient dance before the
layout settles; that accepted residual is stated in the release note rather
than treated as resolved.

The release note is
`.changeset/20260729134719-switching-creating-and-closing-ghostty-tabs-no-l.md`
with contributor `dagrlx`, the #191 reporter. Relevant tests landed in
`Tests/NehirTests/AXEventHandlerTests.swift`,
`Tests/NehirTests/FocusedCreateStabilizationTests.swift`, and
`Tests/NehirTests/ManagedReplacementFocusReconciliationTests.swift`. PR #193's
CI ran `mise run test` successfully (`Swift tests`, 3m38s) and passed
`SwiftLint + SwiftFormat` (43s).

---

## TL;DR

- **Observed.** Switching tabs inside a Ghostty window destroys one AX window id
  and creates another. Nehir has a managed-replacement correlation mechanism
  built exactly to fold that identity churn onto the existing managed entry.
  Across six tab switches in one 14.1 s capture the mechanism **never** paired a
  destroy with a create: all six flushes recorded
  `creates=1 destroys=0 matched=false rekeyed=false replayed=1`.
- **Candidate cause.** The destroy never enters the correlation burst. Ghostty's
  tab teardown is surfaced as a CGS space-destroyed signal while the WindowServer
  surface is still resolvable, so the destroy takes the *deferred* liveness path
  and is later removed by a direct `handleRemoved(token:)` call inside the
  verification task
  (`Sources/Nehir/Core/Controller/AXEventHandler.swift:2305`). That call bypasses
  the funnel that would have enqueued it
  (`:5995-6008` → `:6095` `enqueueManagedReplacementDestroy`). The burst therefore
  only ever holds creates, cannot form a pair (`:6140`
  `matchedManagedReplacementPair`), and replays the create as a brand-new window
  (`:6176-6223` → `:1991` `trackPreparedCreate`) instead of rekeying the existing
  entry (`:6227` → `:5206` `rekeyManagedWindowIdentity`).
- **Consequence observed in layout.** Each tab switch collapses the workspace from
  2 columns to 1 and then inserts a *new* column with a *new* layout node id.
  Column identity, and everything keyed to it, is lost on every tab switch.
- **Falsifier checked.** If the destroy did reach the burst, the capture would
  contain at least one `enqueueManagedReplacementDestroy` record for the Ghostty
  pid, or one flush with `matched=true`. The capture contains **zero** of each.

---

## Reproduction topology

- Single display `ID(displayId: 1)`, main, notched, frame
  `(0.0, 0.0, 2056.0, 1329.0)`, visible frame `(0.0, 0.0, 2056.0, 1290.0)`.
- `displaySpacesMode=enabled`, `focusFollowsMouse=false`,
  `moveMouseToFocusedWindow=false`.
- 7 workspaces, 1 visible. Interaction workspace
  `DA481457-6B27-436E-9965-0F8518A6F2AB` (referred to below as **W-DA48**),
  reported in the viewport trace as `workspace=3`.
- W-DA48 holds exactly two tiled columns at the start of the capture:
  - column 0 — Helium, `WindowToken(pid: 58013, windowId: 13730)`,
    `liveAXFrame={{14.0, 7.0}, {1011.0, 1251.0}}`;
  - column 1 — Ghostty, `WindowToken(pid: 912, windowId: 19475)`,
    `bundleId=com.mitchellh.ghostty`, `title="~"`,
    `liveAXFrame={{1031.0, 7.0}, {1011.0, 1251.0}}`.
- Ghostty (pid 912) also owns two windows parked on the inactive workspace
  `95C7C40B-FAC4-4D7F-B7E2-332BD134678E`: windowIds `13836` and `14060`.
- Action performed during the capture: repeatedly switching between two tabs of
  the Ghostty window on W-DA48, plus one column-width preset cycle.

Ghostty AX enumeration for pid 912 always reports exactly three windows, with the
tab-group window id alternating between `19566` and `19475`:

```text
ax_windows_query pid=912 newContext=false count=3 windowIds=[19566, 14060, 13836]
ax_windows_query pid=912 newContext=false count=3 windowIds=[19475, 14060, 13836]
```

So exactly one of `19475` / `19566` exists at any moment: the tab switch is a
genuine AX identity swap of one logical window, not a second window appearing.

---

## Observed lifecycle of one tab switch

Timeline for the switch at `00:16:21` (all events inlined from the capture;
`t=` values are the capture's own timestamps):

```text
t=00:16:20.969  activation_source_observed pid=912 source=workspaceDidActivateApplication
t=00:16:21.006  window_decision token=W(912/19475) context=focused_admission
                existingMode=nil disposition=managed outcome=trackedTiling
t=00:16:21.010  focused_admission_guard token=W(912/19475) outcome=delayed
                reason=managed_replacement_create
                shouldDelayManagedReplacementCreate=true structuralWorkspaceMatch=true
t=00:16:21.011  create_seen window=19475
t=00:16:21.012  destroy_liveness_decision window=19566 token=W(912/19566)
                origin=cgs_space_destroyed space=3 verify_ws=true ws_pid=912
                outcome=defer reason=window_server_alive
t=00:16:21.093  destroy_liveness_verification token=W(912/19566)
                origin=cgs_space_destroyed ws_alive=true ax=missing_token
                outcome=remove reason=ax_missing_token
t=00:16:21.207  track_prepared_create token=W(912/19475) admissionContext=windowCreate
                mode=tiling structuralWorkspaceMatch=true frame=(1031,71 1011x1251)
t=00:16:21.207  window_admitted token=W(912/19475) admissionContext=windowCreate mode=tiling
```

The corresponding burst records for the same switch:

```text
managedReplacement.enqueued pid=912 workspace=W-DA48 policy=structural
    creates=1 destroys=0 holds=0 deadlineReset=true
enqueueManagedReplacementCreate pid=912 workspace=W-DA48 policy=structural
    token=W(912/19475) windowId=19475 mode=tiling creates=1 destroys=0
    structuralWorkspaceMatch=true bundle=com.mitchellh.ghostty
    role=AXWindow subrole=AXStandardWindow title="~" frame=(1031,71 1011x1251)
scheduleManagedReplacementFlush pid=912 workspace=W-DA48 policy=structural
    delayMillis=150 deadlineReset=true reusedExistingDeadline=false
managedReplacement.flushed pid=912 workspace=W-DA48 policy=structural
    creates=1 destroys=0 holds=0 elapsedMillis=197
flushManagedReplacementBurst pid=912 workspace=W-DA48 policy=structural
    elapsedMillis=197 creates=1 destroys=0 matched=false rekeyed=false replayed=1
replayManagedReplacementEvents pid=912 workspace=W-DA48 count=1
    creates=1 destroys=0 reason=no_match
```

The create side works as designed: `focused_admission_guard` reports
`outcome=delayed reason=managed_replacement_create`, and the create is held in a
`policy=structural` burst with `structuralWorkspaceMatch=true`. The destroy of
the outgoing tab window `19566` never appears in that burst.

### Aggregate over the whole capture

| Record | Count in the capture |
| --- | --- |
| `enqueueManagedReplacementCreate` (pid 912) | 8 |
| `enqueueManagedReplacementDestroy` (any pid) | **0** |
| `flushManagedReplacementBurst` with `matched=true` | **0** |
| `flushManagedReplacementBurst` with `creates=1 destroys=0 matched=false rekeyed=false replayed=1` | 6 |
| `destroy_liveness_decision` with `origin=cgs_space_destroyed … outcome=defer reason=window_server_alive` | every recorded destroy decision for pid 912 |
| `destroy_liveness_verification` with `outcome=remove reason=ax_missing_token` | 6 (3× `19475`, 3× `19566`) |

`window_admitted` fired 42 times and `window_removed` 6 times in 14.1 s, all for
pid 912. The end-of-capture state records
`windowRuntime … replacementCorrelation=0` and
`AXManager … rekeyedWindowIds=0` — no rekey ever happened.

---

## Layout damage produced by the missing correlation

The niri insertion trace records six insertions of the Ghostty tab window into
W-DA48 — one per tab switch. Every one of them shows the column count having
already dropped to 1, and the window landing as a *new* column:

```text
00:16:18  token=W(912/19566) beforeColumns=1 selectedTokenBefore=W(58013/13730)
          selectedColumnBefore=0 reference=focused_token referenceColumn=0 landedColumn=1
00:16:21  token=W(912/19475) beforeColumns=1 selectedTokenBefore=W(58013/13730)
          selectedColumnBefore=0 reference=focused_token referenceColumn=0 landedColumn=1
00:16:22  token=W(912/19566) beforeColumns=1  …  landedColumn=1
00:16:26  token=W(912/19475) beforeColumns=1  …  landedColumn=1
00:16:27  token=W(912/19566) beforeColumns=1  …  landedColumn=1
00:16:28  token=W(912/19475) beforeColumns=1  …  landedColumn=1
```

Three consequences are directly observable.

**1. Column identity is destroyed and recreated.** The workspace's selected
layout node id changes on every cycle:
`NodeId(uuid: E3A2FF2F-BBE0-4E5E-B9CC-87FD84867DAE)` →
`NodeId(uuid: 89E03229-3DD5-472A-95E1-42FC3DC329CC)` →
`NodeId(uuid: DF1BC202-8759-4931-9DBA-56DD51B0A837)`. Anything keyed to the
column node — width spec, insertion position, per-column layout state — cannot
survive a tab switch.

**2. A full relayout and scroll animation runs on every tab switch.** The
viewport collapses to one column and springs back:

```text
00:16:18  relayout.viewportOffsetChanged columns=1 activeColumnIndex=0
          currentOffset=-204.0 targetOffset=-204.0 currentViewStart=-204.0
00:16:18  relayout.viewportOffsetChanged columns=2 activeColumnIndex=1
          currentOffset=-1204.7 targetOffset=-1023.0
          currentViewStart=-197.4 targetViewStart=-6.0 animating=true
00:16:18  scroll_animation_start displayId=1 registered=true
```

**3. Layout selection falls back to the neighbour between switches, and a width
command landed on that neighbour.** Every insertion above records
`selectedTokenBefore=WindowToken(pid: 58013, windowId: 13730)` and
`focusedColumnBefore=0` — the Helium column — because the Ghostty column no
longer exists at that instant. The one width command in the capture resolved
against column 0:

```text
00:16:24 cmd=1 compute kind=toggleColumnWidth(forward) source=presetCycle
         previous=1011.0 currentSpec=proportion(0.5000) nextPreset=2
         newSpec=proportion(0.6500)
         state{columnIndex=0 … window=13730,frame=1011.0,mode=normal}
00:16:24 cmd=1 apply  kind=toggleColumnWidth(forward) targetPixels=1316.1
         newSpec=proportion(0.6500) presetIdx=2 didStartAnimation=true
         after{columnIndex=0 widthSpec=proportion(0.6500) resolvedSpec=1316.1
               targetWidth=1316.1 manual=true … window=13730}
```

That the command was *intended* for the Ghostty column is a **hypothesis** — the
capture records which column the command resolved to, not the user's intent. What
is observed is that the command resolved to column 0 (Helium `13730`), not to the
Ghostty column, and that the layout selection at that moment could not have been
the Ghostty column because it did not exist.

**End state of W-DA48**, compared with the two clean side-by-side columns at the
start:

```text
W(912/19475)    liveAXFrame={{522.0, 7.0}, {1011.0, 1251.0}}   phase=tiled hidden=nil
W(58013/13730)  liveAXFrame={{-800.0, 7.0}, {1316.0, 1251.0}}  phase=tiled hidden=nil
```

The Helium column is 1316 px wide and sits at `x=-800`, mostly off the left edge
of the 2056 px display; the Ghostty column ends at `x≈1533`, leaving roughly
500 px of empty space at the right. The viewport settled at
`currentViewStart=807.6 targetViewStart=807.6` with `columns=2`. Compare the
start-of-capture viewport: `currentViewStart=-6.0 targetViewStart=-6.0`.

---

## Candidate cause, in source

`main` at `eb451326`. Function names are included so the citations stay findable
as line numbers drift.

The synchronous destroy funnel routes a correlatable destroy into the burst
(`AXEventHandler.swift:5995-6008`, in `handleWindowDestroyed`):

```swift
let shouldDelayDestroy = shouldDelayManagedReplacementDestroy(candidate)
…
if shouldDelayDestroy {
    …
    enqueueManagedReplacementDestroy(candidate)
    return
}
processPreparedDestroy(candidate)
```

`shouldDelayManagedReplacementDestroy` (`:6045-6047`) returns true whenever a
correlation policy exists for the destroyed entry's replacement metadata.

But **before** that funnel is reached, `handleWindowDestroyed` can hand the
destroy to a deferred verification instead (`:5921-5941`). When the WindowServer
still resolves the window id to the same pid, the destroy is deferred:

```swift
let windowServerPid = resolveWindowInfo(windowId).map { pid_t($0.pid) }
if windowServerPid == candidate.token.pid {
    …   // outcome: "defer", reason: "window_server_alive"
    scheduleDestroyLivenessVerification(for: candidate.token, origin: origin, …)
    return
}
```

That is exactly what the capture records for every Ghostty tab teardown:
`origin=cgs_space_destroyed … ws_pid=912 outcome=defer reason=window_server_alive`.

`scheduleDestroyLivenessVerification` (`:2219`) then sleeps
`postCreateLifecycleVerificationDelay` (`:912`, `.milliseconds(75)`),
re-enumerates AX for the pid, and — when the window really is gone — removes it
with a **direct** call (`:2305`):

```swift
AXWindowService.invalidateCachedTitle(windowId: windowId)
self.handleRemoved(token: token)
```

`handleRemoved` is the same terminal step that `processPreparedDestroy` (`:6028`)
calls. The deferred path reaches it *without* passing through
`prepareDestroyCandidate` (`:5799`), `shouldDelayManagedReplacementDestroy`, or
`enqueueManagedReplacementDestroy` (`:6095`). No destroy is ever placed in a
burst, so `matchedManagedReplacementPair` (`:6140`) has nothing to pair, and
`replayManagedReplacementEvents` (`:6176`) replays the create through
`trackPreparedCreate` (`:1991`) — a fresh admission — instead of
`completeManagedReplacement` (`:6169`) → `rekeyManagedReplacement` (`:6227`) →
`rekeyManagedWindowIdentity` (`:5206`), which is what preserves the entry and its
layout node.

### Timing relation

The two delays are structurally compatible, so the deferred destroy resolves
inside the create's grace window rather than after it:

- deferred destroy verification: `postCreateLifecycleVerificationDelay = 75 ms`
  (`:912`), plus one AX enumeration round trip;
- structural burst grace: `managedReplacementGraceDelay = 150 ms` (`:904`), via
  `managedReplacementGraceDelay(for:)` (`:7094`) and
  `scheduleManagedReplacementFlush` (`:7108`).

In the `00:16:21` switch this held with margin: the destroy signal arrived at
`t=…21.012`, the verification resolved at `t=…21.093` (81 ms later), and the burst
flushed at `t=…21.207` (`elapsedMillis=197`). The destroy resolution therefore
landed **114 ms before** the flush that failed to match it.

Note that `enqueueManagedReplacementDestroy` (`:6095`) sets
`resetExistingDeadline = isNewBurst || hadPendingCreate`, so a destroy arriving
into a burst that already holds a create restarts the 150 ms grace — a destroy
routed in at `t=…21.093` would extend the flush rather than race it.

### Falsifier

The candidate cause predicts that no destroy for pid 912 ever reaches the burst.
It would be **wrong** if the capture contained any of:

- an `enqueueManagedReplacementDestroy` record for pid 912;
- any `managedReplacement.enqueued` or `flushManagedReplacementBurst` record with
  `destroys` greater than 0;
- any `flushManagedReplacementBurst` with `matched=true` or `rekeyed=true`;
- a non-zero `replacementCorrelation` or `rekeyedWindowIds` in the end state.

The capture contains none of these: `enqueueManagedReplacementDestroy` appears
0 times, every burst record reads `destroys=0`, all six flushes read
`matched=false rekeyed=false`, and the end state reads
`replacementCorrelation=0` and `rekeyedWindowIds=0`.

### What is *not* established

- Whether this is the sole cause of the 50 %-width symptom described in #191.
- Whether the `00:16:24` width command was aimed at the Ghostty column.
- Whether the AX-destroy-notification origin (`ax_destroyed`) reaches the same
  dead end. The capture's AX notification trace contains only
  `AXFocusedWindowChanged pid=912 window=nil`; every destroy in it arrived via
  `origin=cgs_space_destroyed`. The source path at `:5921-5941` is origin-agnostic
  once `verifyWindowServerLiveness` is true, so the same bypass is **expected** on
  the AX origin — but that is a hypothesis, not an observation from this capture.

---

## Relation to #191

#191 reports Ghostty shrinking to half the screen width when Quick Terminal is
open and tabs are switched, described by the reporter as "as if a phantom window
were influencing the layout", with restart or a manual resize as the workaround.

What this capture establishes is the mechanism that would produce a phantom
column: on every tab switch the Ghostty column is torn out of the layout and
re-inserted as a *new* column at `landedColumn=1`, relative to whichever column
happens to be focused at that instant, with a fresh node id and no inherited
width spec. That matches "a new column appeared and everything is now sharing the
width" and matches the workaround (a manual resize re-establishes a width spec; a
restart rebuilds the layout from scratch).

Whether #191's specific 50 % geometry follows from this alone is a **hypothesis**.
The reporter's configuration adds Quick Terminal, which the capture analysed here
did not have open (`overlayCapablePids=0` at both ends of the capture).

---

## Pre-implementation direction and landed expansion

**Invariant to enforce:** a managed window's removal must reach the
managed-replacement correlation mechanism exactly once, regardless of which
lifecycle route decided the window is gone. Correlation eligibility is a property
of the *entry*, not of the code path that observed the teardown.

The change is to the shared mechanism, not to Ghostty or to tabs: the same bypass
applies to any app whose window teardown is surfaced with the WindowServer surface
still resolvable, and to any correlatable destroy that takes the deferred route.

**Shape.** Have the deferred destroy-liveness verification converge on the same
funnel as the synchronous route, instead of calling `handleRemoved(token:)`
directly at `AXEventHandler.swift:2305`. Concretely, at the point where the
verification has decided `shouldRemove`, re-derive a `PreparedDestroy` for the
token and run the existing decision sequence — `shouldDelayManagedReplacementDestroy`
→ `enqueueManagedReplacementDestroy`, else `processPreparedDestroy` — so that a
correlatable destroy joins the burst and an uncorrelatable one removes
immediately, exactly as the synchronous route already behaves.

Constraints this must respect:

- **Derive nothing new.** No new delay constant is needed. The existing
  `postCreateLifecycleVerificationDelay = 75 ms` (`:912`) and
  `managedReplacementGraceDelay = 150 ms` (`:904`) already order correctly, and
  `enqueueManagedReplacementDestroy` resets the grace deadline when a create is
  already pending. If a case is found where the ordering does not hold, the
  correct response is to make the burst wait on the pending verification, not to
  pick a larger literal.
- **No new behavior flag.** The routing decision is already modelled by
  `shouldDelayManagedReplacementDestroy` / the correlation policy. Reuse it rather
  than adding a boolean that distinguishes "deferred" from "synchronous" removal.
- **Preserve the dual-oracle semantics** shipped in `d4cc525c` and the CGS
  protection shipped in `a55b4e33`. The proposal changes *where the removal is
  delivered*, not *whether the window is judged dead*.
- **No migration or compatibility code.** Nothing here is persisted state.

Boundary cases retained as implementation and review criteria:

1. **Destroy with no matching create** (a real window close): the burst holds a
   lone destroy, flushes after the grace delay, and replays it through
   `processPreparedDestroy`. Net effect must equal the immediate-removal
   behavior at baseline commit `eb451326`, delayed by at most the grace window. Confirm this does not regress
   close-focus recovery, which already has a
   `removed_focus_recovery_deferred … reason=pending_managed_replacement` path
   (observed in this capture).
2. **Create arriving after the destroy has already flushed** (grace exceeded):
   must fall back to the behavior at baseline commit `eb451326` — a fresh
   admission — not to a rekey onto a
   removed entry.
3. **Several windows of one pid torn down at once** in one workspace (app quit,
   space teardown): `matchedManagedReplacementPair` (`:6140`) already returns nil
   when the pairing is ambiguous. Verify that an N-destroy burst still resolves to
   N removals rather than an arbitrary pairing.
4. **Verification task cancelled** between the decision and the removal
   (`cancelDestroyLivenessVerification`, `:2322`): must not leave an orphaned
   burst entry that later replays a destroy for a window that was readmitted.
5. **Both tab windows parked on an inactive workspace.** The capture shows pid
   912 also owning `13836` / `14060` on workspace `95C7C40B-…`; the burst key is
   `(pid, workspaceId)`, so cross-workspace churn for one pid must remain in
   separate bursts.

Out of scope for this change: the create-side gap tracked in
[`../planned/20260625-vscode-focused-admission-skips-managed-replacement-rekey.md`](../planned/20260625-vscode-focused-admission-skips-managed-replacement-rekey.md),
and any change to how a width preset resolves its target column.

**Validation outcome.** The focused correlation tests cover matched
destroy/create rekeying and reconciliation. In the real reproduction, the user
confirmed that repeated tab switches no longer destroy and reinsert the layout
column. The same diagnostic shape remains a falsifier: repeated switches should
record destroys joining the correlation burst and completed rekeys; fresh niri
insertions and a changing layout node id on every switch would contradict the
landed behavior.
