# Upstream post-roadmap candidates — 0.5.7 / 0.5.8 / 0.5.9 sweep (2026-07-14 → 2026-07-28)

Sixth post-roadmap triage of `BarutSRB/OmniWM` against Nehir `main`. It continues
the running backport-tracking loop established by the canonical roadmap
([`20260618-upstream-port-roadmap.md`](20260618-upstream-port-roadmap.md)) and the
previous sweep ([`20260714-upstream-post-roadmap-candidates.md`](20260714-upstream-post-roadmap-candidates.md)).

**Sweep range:** every upstream commit after the previous sweep's cutoff `be68cfbf`
("Release 0.5.6") through current upstream `main` HEAD `044441c4` ("Fix fullscreen
close replacement replay"). **72 commits** across releases **0.5.7**, **0.5.8**,
**0.5.9** and post-0.5.9; 48 are behavioural, 24 are release/docs/merge/comment
noise or architecturally N/A (enumerated at the end).

Nehir-side evidence was verified against the main Nehir source tree at `f9aff475`
on 2026-07-28. Upstream commits were read directly from `BarutSRB/OmniWM` via the
`upstream` remote. No Nehir source was modified; this is planning only.

**Method note.** Run as five parallel, non-overlapping triage lanes — (1) AX /
admission / identity lifecycle, (2) Niri layout / orientation / viewport,
(3) focus / workspace navigation / workspace↔monitor moves, (4) workspace bar /
borders / status menu / multitouch input, (5) monitor identity + per-display
config + the upstream issue/PR sweep — then synthesised and cross-reconciled here.
Where two lanes reached different verdicts on the same item, the reconciliation is
recorded explicitly in the section below rather than silently resolved.

**Verdict legend:** 🔴 worth porting · 🟡 conditional-investigate / verify / fold-in /
already-planned · 🟢 already-have / skip / N/A. Effort: XS / S / M / L.

---

## Headline — this sweep found more confirmed defects than any prior one

Twelve items are 🔴 with a source-cited pre-fix shape present in Nehir `main`.
The three highest-confidence, lowest-effort ones:

- **`a4b8611a` — Nehir's primary SkyLight focus path carries the byte-for-byte
  pre-fix key-window event record** (`Sources/Nehir/Core/PrivateAPIs.swift:38-58`:
  a `0xF8`-byte buffer with an all-`0xFF` NaN window-location block at
  `0x20..<0x30`). Upstream adapted AltTab v11.3.1's fix — pad to `0x100`, write a
  finite off-content `(-1,-1)`. XS.
  **Erratum (2026-07-28, runtime).** The code-shape claim holds; the implied user
  impact does not. The upstream symptom could not be reproduced on Nehir `main`
  without the port, nor on upstream OmniWM v0.5.7 itself, on the same macOS build
  as the reporter. Retained as hardening only, no release note. See
  [`20260728-skylight-key-window-nan-location-symptom-not-reproducible.md`](20260728-skylight-key-window-nan-location-symptom-not-reproducible.md).
- **`ac0a0287` — "Hide Empty Workspaces" drops the focused workspace from the bar.**
  `Sources/Nehir/UI/WorkspaceBar/WorkspaceBarDataSource.swift:151-155` filters on
  `hasBarOccupancy` *before* `activeWorkspaceId` is computed, so navigating to an
  empty workspace leaves no item reporting `isFocused`. XS.
- **`a91f20e8` — the Niri viewport is never clamped when a column right of the
  active one is removed.** `removeColumnByIdx`'s `removedIdx > activeIdx` branch
  returns with `viewportNeedsRecalc == false` and no recalculation
  (`Sources/Nehir/Core/Layout/Niri/NiriLayoutEngine+Windows.swift:527-539`);
  `removeWindows` has no content-edge clamp (`:331-342`). S.

Two findings are structural rather than point fixes and change how existing work
should be scoped:

- **The orientation campaign is far less greenfield than the previous sweep
  implied.** Nehir already ships the orientation substrate; what is missing is
  edge wiring plus five orientation-blind subsystems, cleanly stageable into six
  slices (**O1–O6** below). BarutSRB/OmniWM#474 closes on an XS change gated by
  one portrait repro.
- **Nehir's post-layout focus completion has no staleness gate at all**
  (`RefreshPostLayoutAction = @MainActor () -> Void`,
  `Sources/Nehir/Core/Layout/LayoutBoundary.swift:150`), while its *input* side
  already has the `selectionRevision` precedent. Three upstream commits attack
  this; the cheap guards are XS, the general mechanism is a separate design item.

---

## Cross-lane reconciliations

Recorded because lanes reached different conclusions and the resolution matters.

| Item | Conflict | Resolution |
| --- | --- | --- |
| BarutSRB/OmniWM#498 / `a91f20e8` viewport clamp | The issue lane read it as 🟢 already covered by `completed/20260706-stable-viewport-on-window-close-recovery.md`. The Niri lane read the engine source and found the pre-fix shape present. | **🔴 stands.** The Niri lane checked all six candidate Nehir docs individually: every one is about the viewport moving when it should stay (over-eager reveal/recenter) or about *focus* recovery. Upstream's bug is the opposite polarity — the viewport fails to move and straddles vacated space. Net-new. |
| BarutSRB/OmniWM#505 / `a4b8611a` Chrome PWA focus | The issue lane guessed 🟢 "probable N/A, upstream-regression-specific — unverified". The AX lane read `PrivateAPIs.swift`. | **🔴 stands** *(as written; superseded — see erratum)*. Nehir carries the pre-fix bytes regardless of upstream's regression history; the fix is to the shared AltTab-derived event record, not to upstream's 0.5.7 admission cluster. **Erratum (2026-07-28, runtime):** the issue lane's instinct was closer. The bytes are pre-fix, but the symptom is not reproducible here — including on upstream v0.5.7 itself — so the item is hardening, not a defect fix. [`20260728-skylight-key-window-nan-location-symptom-not-reproducible.md`](20260728-skylight-key-window-nan-location-symptom-not-reproducible.md) |
| BarutSRB/OmniWM#488 follow-focus on up/down moves | Issue lane: 🟡 "XS verify, not verified". Focus lane read all five move paths. | **🔴 confirmed.** Three of five paths ignore the setting. |
| BarutSRB/OmniWM#479 trackpad scroll focus | Issue lane: 🟡 "gesture lane, unverified". Focus lane verified. | **🟢 for the feature** (Nehir has it and richer), **🔴 for `7f300c31`(a)** — Nehir also focuses on *cancelled/aborted* gestures. |
| BarutSRB/OmniWM#493 / BarutSRB/OmniWM#486 multitouch | Issue lane: 🟡 unverified. Bar/input lane read the source. | **🔴 confirmed** — see the silent-deafness path below. |
| BarutSRB/OmniWM#511 / `7ea45238` | Issue lane: 🟡 "candidate for the admission lane". AX lane verified. | **🔴 (L1-E)** for the attribute-evidence predicate; 🟡 for the rest. |

**Out-of-range dependency.** `3419f4fe` (focused-sheet rescan exemption) cannot be
transcribed because Nehir has no `systemModalFocusToken`; upstream's comes from
`689974b5` "Track system modal focus separately", dated **2026-06-15 — before this
sweep's cutoff**, and it does not appear in any prior sweep's record. It is
carried forward here as an untriaged upstream commit, not as a finding.

---

## Lane 1 — AX layer, window admission / identity lifecycle, runtime diagnostics

Thirteen commits. Upstream built a `WindowAdmission{Identity,Lifecycle,Retirement,
Retry,Tracking}` subsystem plus an `AXWindowEnumeration` layer that have **no Nehir
counterpart**; the large commits (`fbf8d0f9`, `5ec60b9e`, `fa25338e`, `1ccee8b3`)
are triaged as sub-findings, not diff applies. The value is in four extracted
defects, three of which are 🔴.

| Upstream commit | One-line change | Nehir-equivalent already present? (file:line) | Verdict | Effort | Nehir files |
| --- | --- | --- | --- | --- | --- |
| `a4b8611a` Fix Chrome PWA focus event regression (BarutSRB/OmniWM#505) | Adapt AltTab v11.3.1: pad the SkyLight key-window event record to `0x100` and replace the all-`0xFF` (NaN) window-location bytes with a finite off-content `(-1,-1)`. | **No — Nehir carries the exact pre-fix bytes.** `Sources/Nehir/Core/PrivateAPIs.swift:38-58` (`[UInt8](repeating: 0, count: 0xF8)`, `for i in 0x20..<0x30 { eventBytes[i] = 0xFF }`). This is Nehir's main SkyLight focus path (`focusWindow` at `:60-66`, wired at `Sources/Nehir/Core/Controller/WMController.swift:43`) and is also used by the command palette (`Sources/Nehir/UI/CommandPalette/CommandPaletteController.swift:1041`). **Erratum (2026-07-28, runtime):** symptom not reproducible on Nehir `main` without the port nor on upstream v0.5.7; upstream issue has zero comments and no confirmation. Downgraded to hardening — [`20260728-skylight-key-window-nan-location-symptom-not-reproducible.md`](20260728-skylight-key-window-nan-location-symptom-not-reproducible.md). | **🔴 → 🟡** (hardening) | XS | `Sources/Nehir/Core/PrivateAPIs.swift` |
| `7ea45238` Fix floating window admission and focus (BarutSRB/OmniWM#511, BarutSRB/OmniWM#508) | Normalize unsupported fullscreen-button AX evidence (absent vs. genuine fetch failure); tighten `resolvedAttribute` to require an actual `AXUIElement`; gate size-settable admission deferral on tiling; focus the newest create context during a full rescan. | **Split — L1-E is 🔴.** Nehir has the "non-`AXUIElement` fullscreen-button value ⇒ absent" half (`Sources/Nehir/Core/Ax/AXWindow.swift:719-728`) but not the `resolvedAttribute` tightening, not the absent-vs-failed distinction, and no `shouldDeferAdmission` equivalent. | **🔴** (L1-E) / 🟡 (L1-F, L1-G) | XS / M | `Sources/Nehir/Core/Ax/AXWindow.swift`, `Sources/Nehir/Core/Controller/AXEventHandler.swift` |
| `fa25338e` Harden AX window identity and admission lifecycle | Bind observer subscriptions, frame applications, rebind cleanup and admission retries to exact AX window *incarnations*. | **The observer-incarnation subset is a present Nehir bug (L1-D).** The rest lives in upstream's absent `WindowAdmission*` subsystem; Nehir has zero occurrences of an incarnation concept. | **🔴** (L1-D) / 🟡 (rest) | S / L | `Sources/Nehir/Core/Ax/AppAXContext.swift` |
| `fbf8d0f9` Bound AX full-rescan discovery | Route evidence-backed apps through persistent AX contexts, probe evidence-free regular apps with bounded one-shot enumeration, carry captured evidence so MainActor reduction does no live AX reads. | **No — Nehir is the pre-fix design.** `fullRescanEnumerationSnapshot()` enumerates only PIDs with WindowServer evidence (`Sources/Nehir/Core/Ax/AXManager.swift:496-580`); the reduction loop does live AX reads per candidate on the MainActor (`Sources/Nehir/Core/Controller/LayoutRefreshController.swift:1400-1421` → `Sources/Nehir/Core/Controller/WMController.swift:2724-2749`). | **🟡** (L1-A / L1-B) | L | `AXManager.swift`, `LayoutRefreshController.swift`, `WMController.swift` |
| `5ec60b9e` Harden window admission identity lifecycle | Pure observed-identity lookup, evidence-bound retry state, alias history bounded to two generations, single owner-local retirement transaction. | **Architecturally absent.** Equivalent logic is inlined in `AXEventHandler.swift:6660-6715` and `AXManager.rekeyWindowState` (`AXManager.swift:321-360`). Alias chain is collapsed to one hop and pruned (`:1107-1117`) but not generation-bounded (L1-H). | **🟡** (sub-findings only) | L | `AXEventHandler.swift`, `AXManager.swift` |
| `1ccee8b3` Complete window admission reliability hardening | Adds `AXCallbackGenerationRegistry`: a global *service generation* fencing every AX callback by observer pointer. | **Nehir has no such fence (L1-C).** Nehir's `LockedWindowGenerationMap` (`Sources/Nehir/Core/Ax/AppAXContext.swift:34-63`, used as `frameWriteGenerations` at `:105`) is keyed by **window id** and fences **frame writes** — a different concern. The two registries do not overlap. | **🟡** (L1-C only) | M | `AppAXContext.swift`, `AXManager.swift`, `RunLoopJob.swift` |
| `3f3d2fb9` Add structured window-admission tracing | Typed trace schema, generation-aware finalization targets, JSON window-classification fixture corpus + reproducer. | **Tracing: comparable already.** `Sources/Nehir/Core/Controller/RuntimeDiagnosticsCoordinator.swift` owns capture/export; the admission decision line already carries ~25 fields (`AXEventHandler.swift:490-509`). **The genuinely absent piece is the classification-fixture corpus** — `Tests/NehirTests/Fixtures/` holds only `canonical-settings.toml`. | **🟡** (fixture corpus only) | M | new `Tests/NehirTests/Fixtures/WindowClassification/` + regression test |
| `3419f4fe` Preserve focused sheets during full rescan | Exempt the focused `AXSheet`, validated against parent window id and WindowServer info, from full-rescan removal. | **Absent, blocked on a missing concept.** The exemption seam exists and is the right shape (`LayoutRefreshController.swift:1682-1727`, template at `:1801-1836`) and `ManagedReplacementMetadata` carries `role`/`parentWindowId` (`Sources/Nehir/Core/Workspace/WindowModel.swift:15`), but Nehir has **no `systemModalFocusToken`** — system-modal is tracked only for border suppression (`Sources/Nehir/Core/Border/FocusBorderController.swift:370-380`). Depends on out-of-range `689974b5`. | **🟡** (needs a repro + a `689974b5` decision) | M | `LayoutRefreshController.swift`, `WorkspaceManager.swift`, `FocusBorderController.swift` |
| `348232a0` Handle terminal AX frame refusals | Quarantine repeatedly-unmanageable tiling incarnations from frame writes. | **Diverged by design, and upstream regressed on it.** Nehir has the retry-budget half (`AXManager.swift:715-745`, `:930-990`) but deliberately answers refusals by inferring a minimum size and feeding it back into layout — `completed/20260619-m1-refused-frame-feedback-characterization.md`, `completed/20260707-persist-inferred-resize-minimum-across-lifecycle.md`; the size-quantum companion was rejected in `noop/20260618-upstream-size-quantum-rejected.md`. BarutSRB/OmniWM#518 reports the quarantine broke Terminal.app column stacking upstream. | **🟢** (do not port) | — | none |
| `780cf917` Fix ghost windows after Chrome closes (BarutSRB/OmniWM#483) | Split CGS destroy handling: space-scoped `.destroyed` keeps liveness guards, `.closed` always tears down. | **Already have, arrived independently and earlier.** `AXEventHandler.swift:1087-1097` routes `.destroyed(windowId, spaceId)` with `spaceId == 0` to `handleCGSWindowClosed`, else to `handleCGSSpaceWindowDestroyed`; the handlers differ exactly on `verifyWindowServerLiveness` (`:1831-1852`). Owned by `completed/20260707-verify-liveness-before-honoring-ax-destroy.md` and `completed/20260707-final-destroy-liveness-dual-oracle.md`. | **🟢** | — | none |
| `099f5b73` Restore verified AX parking for hidden windows | Restore terminal AX reconciliation after SkyLight parking, track park generations, retry verified park writes. | **Already have, via a more developed divergent design.** Nehir parks with a synchronous verified AX write with `AXEnhancedUserInterface` temporarily disabled and no SkyLight move (`LayoutRefreshController.swift:3036-3115`), plus verification, a mismatch trace (`:2910-2960`) and a two-stage delayed re-verify (`:3123-3160`). Owned by `completed/20260704-dock-edge-shield-and-parking-lessons.md`. | **🟢** | — | none |
| `61542a3c` Keep surfaces cleared after service shutdown | `SurfaceReconciler.cleanup()` also clears queued reconcile flags. | **N/A — no equivalent component.** Nehir's `Sources/Nehir/Core/Surface/SurfaceCoordinator.swift` is a hit-testing/capture registry, not a desired-scene reconciler; overlay surfaces are torn down explicitly on stop (`Sources/Nehir/Core/Controller/ServiceLifecycleManager.swift:575-578`). See BarutSRB/OmniWM#496 below for the one residual verify. | **🟢** | — | none |
| `58580ab5` Correlate issue reports with diagnostic artifacts | Build issue attachments from fresh diagnostics; bounded evidence chunks. | **N/A — Nehir has no Report Issue feature.** It is planned: `planned/20260621-send-reports.md`. Useful design reference when that is picked up. | **🟢** | — | none |

### Lane 1 sub-findings

- **L1-D — per-app AX observer is not re-subscribed when a window id is reused by a
  new `AXUIElement`. 🔴, S.** In `AppAXContext.getWindowsAsync`'s enumeration loop
  (`Sources/Nehir/Core/Ax/AppAXContext.swift:479-490`), `newWindows[windowId] = element`
  overwrites the element map while the subscription check is
  `if subscribedWindows[windowId] == nil` (`:485`) — keyed on **presence of the
  window id, not element identity**. When an app re-creates a window resolving to
  the same `CGWindowID` under a new `AXUIElement`, `subscribedWindows[windowId]`
  keeps the **stale** element, so `kAXUIElementDestroyed` / `kAXWindowMiniaturized`
  for the live incarnation are never delivered while the dead element's
  notifications keep arriving. `rekeyWindow` (`:532-565`) handles the *different-id*
  case correctly, so only same-id/new-element is exposed. Fix shape: compare
  `subscribedWindows[windowId] != element`, remove the stale subscription, add the
  new one. **Not reproduced at runtime** — gate a plan on a repro or a unit test
  through `installSubscribedWindowsForTests` (`:594-601`). Symptom class matches
  `discovery/20260628-stale-floating-entry-lingers-after-surface-destroyed.md` and
  the Electron re-creation cases in `discovery/20260625-vscode-editor-unmanaged-until-clicked.md`.

- **L1-E — `hasResolvedAttribute` counts failed/null AX attribute slots as "button
  present". 🔴, XS.** `Sources/Nehir/Core/Ax/AXWindow.swift:689-692` returns true for
  any non-nil value that is not an `NSError`. Nehir calls
  `AXUIElementCopyMultipleAttributeValues` with
  `AXCopyMultipleAttributeOptions(rawValue: 0)` (`:583-588`) — **without**
  stop-on-error — so an unsupported or transiently-failing slot comes back as a
  non-nil `CFNull` or an `AXValue` wrapping an `AXError`, never as an `NSError`.
  Nehir's own diagnostics formatter proves it expects those shapes
  (`describeAttributeValue` has explicit `NSNull` and non-`AXUIElement` branches,
  `:609-629`). Consequence: `hasCloseButton` / `hasZoomButton` / `hasMinimizeButton`
  (`:735-738`) read **true** for button-less windows, suppressing two floating rules
  in `heuristicDisposition` — `accessoryWithoutClose` (`:777-782`) and
  `noButtonsOnNonStandardSubrole` (`:784-789`) — so a fixed-size helper window is
  classified `.managed` and tiled. Upstream's fix is one line: require
  `CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID()`. No planning-branch
  doc covers this predicate. **Confirm with a `describeAttributeValue` capture on a
  real button-less window first** — tightening the predicate changes classification
  for every window and needs the fixture corpus (from `3f3d2fb9`) landed alongside.

- **L1-C — AX callback fencing across a service restart. 🟡, M.** Nehir's
  `AXManager.cleanup()` destroys every context from a detached `Task { @MainActor }`
  (`AXManager.swift:426-430`), so between `cleanup()` returning and that task
  running, per-app AX observer callbacks (`AppAXContext.swift:113-115`) can fire
  into a stopped runtime. `ServiceLifecycleManager.stop()` nils those three closures
  first (`ServiceLifecycleManager.swift:558-560`) — a partial mitigation. The hole is
  narrower than upstream's, and the only same-process stop→start path today is
  onboarding. Plan it **together with**
  `planned/20260714-reinstall-ax-observers-after-service-restart.md`.

- **L1-A / L1-B — full-rescan discovery bounds. 🟡, M.** (A) The MainActor reduction
  issues live `collectWindowFacts` / `isFullscreen` per candidate
  (`WMController.swift:2724-2749`); per-app enumeration is timeout-bounded
  (`perAppTimeout = 0.5`, `AXManager.swift:12`) but the reduction reads are not.
  (B) `AXManager.swift:543-546` never enumerates an app whose windows are invisible
  to both SkyLight and CGWindowList — the same symptom family as
  `discovery/20260625-vscode-editor-unmanaged-until-clicked.md`,
  `discovery/20260707-external-display-column-admission-click-required.md` and
  `completed/20260701-startup-full-rescan-under-enumerates-multi-window-app.md`.
  Upstream's bounded one-shot probe is a plausible structural answer to that whole
  cluster, but adopting it means enumerating every regular running app on every full
  rescan — a cost/product call, not a bug fix.

- **L1-F / L1-G / L1-H — 🟡, verify-first.** No absent-vs-failed distinction for AX
  evidence (`AXWindow.swift:719-728` leaves `attributeFetchSucceeded == true` on a
  transient error, producing a confident `.floating` instead of defer-and-retry);
  no uniform `isMeaningfulAdmissionFrame` guard (ad-hoc `frame.isNull || frame.isEmpty`
  at `AXEventHandler.swift:3079`, `:5639`, `:6144` — the shape
  `completed/20260707-thunderbird-gecko-dialog-still-tiles-frame-isempty-guard-defeats-fix.md`
  already records as fragile); alias chain has no generation bound, so the resolver
  at `AXManager.swift:1082-1090` can forward a recycled `CGWindowID` to an unrelated
  live window.

**Prior-sweep items re-verified at `f9aff475`:** the observer-reinstall bug
(`6808e44c`) is **still unfixed on `main`** — `AXManager.init()` remains the only
caller of `setupTerminationObserver()`/`setupLaunchObserver()` (`AXManager.swift:87-90`),
`cleanup()` nils both (`:415-424`), `ServiceLifecycleManager.stop()` calls
`cleanup()` (`:580`) and `startServices()` (`:77-137`) never reinstalls;
`planned/20260714-reinstall-ax-observers-after-service-restart.md` owns it and the
`impl-reinstall-ax-observers` branch has not merged. `RunLoopJob` still carries the
pre-fix shape (🟡, pair it with the observer fix).

---

## Lane 2 — Niri layout engine: orientation, viewport, sizing, animation

| Upstream commit | One-line change | Nehir-equivalent already present? (file:line) | Verdict | Effort | Nehir files |
| --- | --- | --- | --- | --- | --- |
| `a91f20e8` Clamp Niri viewport to remaining content after window removal | Clamp settled view origin so it never extends past surviving columns; report via `viewportNeedsRecalc`. | **No.** `removeColumnByIdx`'s `removedIdx > activeIdx` branch only clears `activatePrevColumnOnRemoval` and returns with `viewportNeedsRecalc == false` (`Sources/Nehir/Core/Layout/Niri/NiriLayoutEngine+Windows.swift:527-539`); `removeWindows` returns without a content-edge clamp (`:331-342`). Identical pre-fix shape, including the stale-restore branch (`:486-516`). | **🔴** | S | `NiriLayoutEngine+Windows.swift` |
| `53901835` Fix Niri viewport correction after window removal | Restrict correction to real *column* removals, compute bounds on the primary axis, preserve centering policy, carry "a column disappeared" through refresh coalescing. | **No, and the seam is missing.** `NiriWindowRemovalSeed` has no `removedColumn` flag (`Sources/Nehir/Core/Layout/LayoutBoundary.swift`); Nehir has no `centerFocusedColumn` setting (`ResolvedNiriSettings` is `defaultColumnWidth` / `loneWindowPolicy` / `infiniteLoop`, `Sources/Nehir/Core/Config/MonitorNiriSettings.swift:60-64`) and no `computeVisibleOffset`. | **🔴** (port the intent, not the diff) | M | `NiriLayoutEngine+Windows.swift`, `LayoutBoundary.swift`, `LayoutRefreshController.swift`, `NiriLayoutHandler.swift` |
| `044441c4` Fix fullscreen close replacement replay | Tag each destroy with its evidence (`transientLifecycle` vs definitive `windowClosed`), carry it through managed-replacement burst correlation, refuse the native-fullscreen "temporarily unavailable" shortcut for definitive closes. | **No — the same evidence loss exists.** Nehir *has* the richer origin (`handleCGSWindowClosed` → `handleWindowDestroyed(..., origin: .cgsWindowClosed)`, `Sources/Nehir/Core/Controller/AXEventHandler.swift:1841-1852`, `:5698-5702`) but `PreparedDestroy` does **not** carry it (`:758-774`), so the delayed managed-replacement branch calls `handleNativeFullscreenDestroy` with no evidence gate (`:5836`) and `processPreparedDestroy` → `handleRemoved(token:)` loses it (`:5868`, `:2326-2340`). The burst queue also drops a later stronger-evidence destroy instead of upgrading it (`:801-804`). | **🔴** | M | `AXEventHandler.swift` |
| `12f8ee43` Route Niri directions by monitor orientation | Resolve primary/secondary axis from monitor orientation in focus, move, edge detection, animation; flip the vertical primary-step sign. | **Partial — substrate yes, wiring no.** See O1–O3. | **🔴** (O1/O2) / 🟡 (O3) | S → M | `Direction.swift`, `NiriLayoutHandler.swift`, `NiriNavigation.swift` |
| `f54b28d6` Complete orientation-aware Niri layout and sizing | Makes the whole Niri surface orientation-relative, plus a `column`→`container` / `width`→`primarySpan` rename across config, IPC, CLI, UI. | Decomposes into O1–O7. | mixed | see below | see below |
| `4504522d` Prevent vertical Niri animation bleed | Re-check a visible container against neighbouring-monitor overflow at render time; add a monitor-plane clamp and a y-containment frame. | **No.** Nehir carries the pre-fix `ContainerOverflowRegion` helper set (`Sources/Nehir/Core/Layout/Niri/NiriLayout.swift:83`, `:413-441`, `:442-510`) with no live re-check on the `.visible` branch (`:272-296`), **and has no per-window monitor-plane clamp at all** — `screenClampRect` does not exist in the tree; the animated frame is written unclamped (`:1067-1078`). | **🟡** (needs a repro) | M | `NiriLayout.swift`, `NiriNode.swift`, `NiriLayoutEngine+Animation.swift` |

### The orientation campaign, decomposed

**What Nehir already has** (verified, so this is not greenfield): a persisted
per-monitor orientation override with auto-detection
(`Sources/Nehir/Core/Config/MonitorOrientationSettings.swift`,
`settings.effectiveOrientation(for:)`, `NiriMonitor.orientation` at
`Sources/Nehir/Core/Layout/Niri/NiriMonitor.swift:24,44`);
`Direction.primaryStep(for:)` / `secondaryStep(for:)`
(`Sources/Nehir/Core/Controller/Direction.swift:21-57`); a fully
orientation-parameterised pure layout (51 `orientation` references in
`Sources/Nehir/Core/Layout/Niri/NiriLayout.swift`); orientation-generic viewport
geometry (`ViewportState+Geometry.swift:341-360`); container height state
(`NiriNode.swift:407-411`, `:578`, `:614-620`); and `NiriOperationContext.orientation`
threaded into move / consume-or-expel / toggle-tabbed / active-column rebase
(`NiriLayoutHandler.swift:2375-2390`, `:2417`, `:2515`, `:2300-2320`).

| # | Sub-change | Nehir state (file:line) | Verdict | Effort |
| --- | --- | --- | --- | --- |
| **O1** | Directional **focus** routed by orientation | **Absent.** Both `engine.focusTarget(...)` call sites omit `orientation:` and fall back to `.horizontal` (`NiriLayoutHandler.swift:1521-1528`, `:1736-1744`); the pre-call span resolution fills only `cachedWidth` (`:1517-1519`). This is precisely BarutSRB/OmniWM#474. | **🔴** | XS–S |
| **O2** | Vertical **primary-step sign** | Nehir maps `.vertical` primary to `down: 1 / up: -1` (`Direction.swift:30-37`); `12f8ee43` flipped upstream to `up: 1 / down: -1`. Nehir's own stacking convention must be confirmed against `NiriLayout.swift:1013-1065` on a real portrait display — shipping O1 with the wrong sign inverts focus rather than fixing it. **Not confirmed; needs a portrait repro.** | **🔴** (blocks O1) | XS + repro |
| **O3** | Split `moveWindow` into cross-container vs within-container; orientation-aware edge detection | **Absent.** `moveWindow(direction:)` selects its animation/commit path on literal `direction == .left \|\| .right`, so on portrait it takes the *simple* commit for an in-column reorder and the *predicted-animation* commit for a cross-column move — inverted. `windowMoveEdgeResult` is orientation-blind (`:2560-2574`); `consumeOrExpelWindow(direction:)` guards on literal `.left`/`.right` and is a no-op on the portrait primary axis. Also a **product decision**: upstream chose "Move Up/Down always reorders within the container, on every orientation". | **🟡** (decision first) | S–M |
| **O4** | Container **move animation** on the vertical axis | **Absent.** `NiriContainer.animateMoveFrom` only fires for `displacement.x != 0`; `renderOffset` always returns `CGPoint(x:…, y: 0)` (`NiriNode.swift:429-462`); `offsetMoveAnimCurrent` is x-only (`:477`). On portrait, column insert/remove/reorder render as instant jumps. | **🔴** | S |
| **O5** | **Gesture** axis by orientation | **Absent.** `ViewportState+Gestures.swift:149` hard-codes `orientation: .horizontal`, and `MouseEventHandler.swift` contains zero `orientation` references. | **🔴** | M |
| **O6** | **Sizing** commands as primary/secondary span | **Absent.** `NiriLayoutEngine+Sizing.swift` has zero `orientation` references; the command set is width-shaped (`toggleColumnWidth:453`, `setColumnWidth:582`, `toggleFullWidth:662`, `expandColumnToAvailableWidth:736`). Interactive move/resize and restore are equally blind; `PersistedNiriColumnState` persists `width`/`isFullWidth` only (`Sources/Nehir/Core/Reconcile/PersistedWindowRestoreCatalog.swift:10-22`). | **🟡** (largest slice) | L |
| **O7** | `column`→`container`, `width`→`primarySpan` rename across config / IPC / CLI / UI | **Do not port.** Nehir's Niri config model already diverged (`MonitorNiriSettings` is `balancedColumnCount` + `loneWindowPolicy`, `Sources/Nehir/Core/Config/MonitorNiriSettings.swift:16-17`). Upstream shipped this as a **hard break** — dropped the `singleWindowAspectRatio` coding key and the `column_width` parse aliases with no migration — conflicting with Nehir's config-migration policy (`completed/20260616-unified-config-diagnostics-and-migration-policy.md`, `completed/20260621-omniwm-410-settings-toml-unknown-keys-roundtrip-loss.md`). | **🟢** (skip the rename) | — |

**Staging.** O1+O2 are a single XS change behind one repro (two call sites + a sign
decision) and directly close BarutSRB/OmniWM#474. O4 is self-contained in `NiriNode`.
O5 touches the gesture path only. O3 needs a product decision first. O6 can be
deferred indefinitely. **Nothing in O1–O5 changes horizontal-monitor behaviour**,
because every path they touch resolves to the current constants when
`orientation == .horizontal` — that is why the campaign is stageable.

**Effect on the two planned width docs.** `f54b28d6` **does not invalidate**
`planned/20260621-omniwm-295-niri-window-width-preservation.md` — that mechanism is
orientation-agnostic and upstream's version remains the reference impl. It **does**
change the vocabulary of `planned/20260621-omniwm-283-per-app-initial-column-width.md`:
upstream's app rule is now `initialContainerPrimarySpan` (orientation-relative), not
`initialColumnWidth`. Since Nehir has no such field yet, the naming decision is free
**now** and expensive later (a persisted app-rule key rename would need a migration).
**Recommend amending that plan** to introduce an orientation-relative primary-span
field from the outset, even if the initial implementation resolves only the
horizontal case.

**Porting cautions for the viewport clamp**, stated as unverified: (a) `removeWindows`
already has an `ensureSelectionVisible` fixup at `NiriLayoutEngine+Windows.swift:313-329`
gated on `viewportNeedsRecalc`, so a new clamp must be ordered after it and must not
double-animate; (b) `53901835`'s centering-preservation logic has **no Nehir
counterpart** and must be rewritten against Nehir's reveal-style / `LoneWindowPolicy`
model — a straight port would not compile and would re-introduce the recenter
behaviour that `discovery/20260727-column-width-cycle-recenters-viewport-multi-column.md`
is trying to remove. Sequence it after, or jointly with, that work.

---

## Lane 3 — Focus semantics, workspace navigation, workspace↔monitor moves

| Upstream commit | One-line change | Nehir-equivalent already present? (file:line) | Verdict | Effort | Nehir files |
| --- | --- | --- | --- | --- | --- |
| `b35d39d4` + `6d516923` + `9064f502` Follow focus on up/down and column moves to workspace | Route all workspace-move handlers through one `finishWorkspaceMove` that honours the follow-focus setting; hoist `stopScrollAnimation(sourceMonitor)` out of the follow branch. | **No — Nehir has the identical bug.** `moveWindowToAdjacentWorkspace` (`Sources/Nehir/Core/Controller/WorkspaceNavigationHandler.swift:693-728`), `moveColumnToAdjacentWorkspace` (`:730-793`) and `moveColumnToWorkspace(rawWorkspaceID:)` (`:799-861`) all unconditionally call `resolveAndSetWorkspaceFocusToken(for: sourceWs)` and focus back on the source. Only `moveFocusedWindow(toRawWorkspaceID:)` (`:883`) and `moveWindowToWorkspaceOnMonitor` (`:1057`) read `settings.focusFollowsWindowToMonitor`. The setting exists and is user-visible ("Follow Window to Workspace", `Sources/Nehir/UI/BehaviorSettingsTab.swift:47`, default `false`). The same three paths plus both branches of `moveWindowToWorkspaceOnMonitor` (`:1055-1092`) also never stop the source monitor's scroll animation. | **🔴** | S | `WorkspaceNavigationHandler.swift` + new behaviour tests |
| `ea490f8e` Preserve focus after workspace transition invalidation | Guard the navigate-to-window post-layout focus on workspace/entry still matching; also run it on the invalidated path. | **No.** `navigateToWindowInternal` commits an unguarded closure — `commitWorkspaceTransition(reason:.workspaceTransition) { controller?.focusWindow(token, reason:.windowActionRefreshCompletion) }` (`Sources/Nehir/Core/Controller/WindowActionHandler.swift:531-536`). No `activeWorkspace()?.id == workspaceId` check, no `entry(for:)?.workspaceId` check. | **🔴** (cheap guard subset) | XS | `WindowActionHandler.swift` |
| `e75bc2a5` Harden workspace move focus handoff | Recompute the focus token *inside* the post-layout closure and re-verify active workspace + entry membership; add `.alwaysFollow` for window-to-monitor moves. | **No.** Nehir resolves `focusToken` eagerly *before* `commitWorkspaceTransition` in every move path (`WorkspaceNavigationHandler.swift:715`, `:779`, `:848`, `:994`, `:1078`) and focuses it unconditionally. The `.alwaysFollow` half is **N/A** — Nehir has no window-to-monitor directional move; the bindings were deliberately removed, asserted by `Tests/NehirTests/SettingsStoreTests.swift:709-722`. | **🔴** (recompute-and-verify half) | S | `WorkspaceNavigationHandler.swift` |
| `7f300c31` Fix trackpad gesture focus finalization | (a) Focus only on *completed* gestures, not cancel/abort; (b) preserve a settled Niri viewport for pointer-origin focus echoes. | **(a) No — Nehir has the defect.** `finalizeOrCancelCommittedGesture` has no `shouldFocusSelection` parameter (`Sources/Nehir/Core/Controller/MouseEventHandler.swift:2024-2028`) and is invoked identically from the `.ended` **and** `.cancelled` phases (`:1579-1594`) and from `abortActiveGestureIfNeeded()` (`:2273-2302`). **(b) Partial.** `PreserveActiveViewportReason` (`Sources/Nehir/Core/Controller/AXEventHandler.swift:37-47`, `:4628-4640`) preserves only while motion is in flight, never for an echo arriving after the viewport settled. | **🔴** (a) / **🟡** (b) | S / M | `MouseEventHandler.swift`, `AXEventHandler.swift` |
| `2a7041d8` Fix Focus Previous with confirmed focus history | Anchor Focus Previous on the *observed frontmost* window; restrict the global MRU to confirmed managed focus. | **Both halves absent.** Nehir anchors on the active workspace's `state.selectedNodeId` (`Sources/Nehir/Core/Controller/NiriLayoutHandler.swift:1571-1607`) — the exact pre-fix shape. Its MRU is engine focus *timestamps* written at optimistic selection time: `activateNode` (`:2233-2236`), new-window admission (`:1022`), gesture selection (`MouseEventHandler.swift:2388`). So an unconfirmed focus request still lands in the MRU. | **🔴** (anchor) / **🟡** (confirmed-only MRU) | S / M | `NiriLayoutHandler.swift`, `MouseEventHandler.swift` |
| `47aca7d5` Fix workspace-transition focus completion | Re-key post-layout focus on a stable handle, gate on `postLayoutGateWorkspaceIds`, skip if a newer focus intent was issued. | **Absent as a mechanism.** `commitWorkspaceTransition` takes only `affectedWorkspaces`/`reason`/`postLayout` (`Sources/Nehir/Core/Controller/LayoutRefreshController.swift:915-926`) — no gate parameter, no invalidated action. Nehir has no `IntentLedger`; the nearest analogue is `FocusBridgeCoordinator.activeManagedRequest` with a monotonic `requestId` (`Sources/Nehir/Core/Controller/KeyboardFocusLifecycleCoordinator.swift:32-49`). | **🟡** (needs Nehir-shaped design) | M | `LayoutRefreshController.swift`, `WindowActionHandler.swift`, `KeyboardFocusLifecycleCoordinator.swift` |
| `9babdb12` + `a5064c50` Workspace moves between monitors + hotkeys | Non-swapping directional workspace→monitor moves via a **runtime-only monitor override** distinct from configured Home Monitor, with an explicit `force` flag, plus IPC/CLI and four unbound hotkeys. | **Absent — and this contradicts an existing Nehir plan.** See sub-finding below. `moveWorkspaceToMonitor(_:to:)` (`Sources/Nehir/Core/Workspace/WorkspaceManager.swift:3446-3467`) and `assignWorkspaceToMonitor` (`:3520-3529`) are both gated by `isValidAssignment` (`:4301-4309`). `Tests/NehirTests/SettingsStoreTests.swift:723-729` asserts the `moveWorkspaceToMonitor.*` action ids are absent. | **🟡** (revise the plan first) | L | `WorkspaceManager.swift`, `WorkspaceNavigationHandler.swift`, `HotkeyCommand.swift`, `ActionCatalog.swift`, `SettingsStoreTests.swift` |
| `6a7f0aeb` Focus snapped column window when trackpad scroll gesture ends | Apply AX focus once per gesture to the snapped column's window. | **Already have, and richer.** `finalizeOrCancelCommittedGesture` focuses the synced selection (`MouseEventHandler.swift:2185-2199`), preceded by a keyboard-focus-border render and a `suppressMouseMoveToFocusedWindow` warp guard. | **🟢** | — | none |

### Lane 3 sub-findings

**`planned/20260619-nehir-62-move-workspace-to-monitor.md` must be revised before
delegation.** The plan's semantics step says to move the workspace with
`assignWorkspaceToMonitor` + `setActiveWorkspace`. Both are gated by
`isValidAssignment(workspaceId:monitorId:)` (`Sources/Nehir/Core/Workspace/WorkspaceManager.swift:4301-4309`),
which returns true **only when the workspace is already on the target monitor**;
for a workspace with a configured Home Monitor, `effectiveMonitor` returns that home
monitor unconditionally (`:4272-4278`), so the move is refused outright. This is not
inference — it is asserted as intended by
`Tests/NehirTests/WorkspaceManagerTests.swift:900-928`
(`moveWorkspaceToForeignMonitorIsRejectedWhenHomeMonitorDiffers`). The source
discovery flagged exactly this as an unresolved risk
(`discovery/20260619-nehir-62-move-workspace-to-next-monitor.md`); the answer is that
it **cannot** be reassigned under the current model.

Recommended revisions: (1) replace the mechanism with a Nehir `runtimeMonitorOverride`
equivalent or an explicit `force:` parameter that bypasses `isValidAssignment`, and
state which — without it the command silently no-ops for exactly the users who
configure home monitors; (2) decide the Home-Monitor interaction policy explicitly
(survive a settings reload? a display reconnect? upstream clears on reload, defers
unsafe clears, re-resolves on reconnect); (3) **keep Nehir's cyclic `.next/.previous`
UX** — that is what Nehir #62's reporter asked for — but update
`Tests/NehirTests/SettingsStoreTests.swift:723-729` in the same change; (4) add the
commit-path concerns upstream found the hard way (Niri monitor-geometry cache
invalidation, cancelling in-flight source-monitor viewport motion) — the plan
mentions neither; (5) ship the bindings **unassigned** — the plan's proposed
`Ctrl+Cmd+→/←` collides with the `focusMonitorLast` neighbourhood. **Verdict: not
superseded, but materially contradicted on its implementation mechanism.**

**Follow-focus: keep it a setting, do not make it unconditional.** The setting
already exists, is user-visible and defaults to `false`
(`SettingsStore.swift:37`, TOML `focus.followsWindowToMonitor` via
`CanonicalTOMLConfig.swift:292`, `SettingsExport.swift:134`), so making the three
unaware paths unconditional-follow would silently change behaviour for existing
users. Port the upstream shape: one helper reading the setting, all five paths
routed through it — which fixes the `stopScrollAnimation` asymmetry for free.

**Trackpad focus vs. Nehir's known gesture defects.**
`discovery/20260622-workspace-bar-freezes-on-gesture-with-non-managed-focus.md` is
**resolved and superseded** — its root cause was the gesture-end focus side effects
being gated behind `!isNonManagedFocusActive`; current source has no such gate (the
flag is read only for a trace field, `MouseEventHandler.swift:2183`, `:2216`) and the
bar is now a reactive lens (`completed/20260623-workspace-bar-reactive-viewport-lens.md`).
`discovery/20260627-trackpad-fling-snap-overshoot-to-neighbor-column.md` is **directly
aggravated** by the existing focus call — Nehir already focuses whatever column the
sometimes-wrong momentum snap chose, so an overshoot now also steals keyboard focus;
`7f300c31`(b) mitigates only the *echo* half, so the overshoot discovery's snap
retuning remains the primary fix. The other two gesture discoveries are orthogonal.

**Post-layout staleness — the structural gap.** Nehir's post-layout action is a bare
closure with no seq, no domain and no invalidated variant
(`Sources/Nehir/Core/Layout/LayoutBoundary.swift:150`), executed unconditionally
(`LayoutRefreshController.swift:532-534`, `:2191-2193`) and forwarded verbatim
through every coalesce/upgrade/cancel path (`:1976`, `:1992-2095`, `:2337-2338`).
Nehir's *input* side already has the narrower `selectionRevision` guard
(`WorkspaceManager.swift:1785`, `:3653-3663`, consumed at `NiriLayoutHandler.swift:1155`),
landed per `discovery/20260618-stale-session-selection-revision-guard.md`. That is the
precedent to generalise. Note this is a **different problem** from Nehir's
stale-non-managed-focus cluster (`discovery/20260708-stale-nonmanaged-focus-suppresses-managed-selection-and-window-move.md`
and siblings), which is an *input-side* failure where the command never runs; these
upstream commits are an *output-side* failure where the command ran and the callback
then fires against a stale world. Design it around `selectionRevision` +
`FocusBridgeCoordinator.requestId`, **not** by transplanting upstream's
`InvalidationDomain`/`isSeqCurrent`, which sits on the never-adopted WorldStore.

---

## Lane 4 — Workspace bar, borders / window corners, status menu, multitouch input

Four of the six workspace-bar commits are already in Nehir — two of them
(`1f9576f0`, `e2e661b4`) **originated in Nehir**; `1f9576f0`'s own commit message
reads *"Ported from apphane-dev/nehir"*, which settles the previous sweep's
unconfirmed 🟡 on PR BarutSRB/OmniWM#478.

| Upstream commit | One-line change | Nehir-equivalent already present? (file:line) | Verdict | Effort | Nehir files |
| --- | --- | --- | --- | --- | --- |
| `ac0a0287` Keep the active workspace on the bar when hiding empty ones | Hide-empty filter keeps the workspace you are standing on. | **No — the pre-fix code is present verbatim.** `workspaces = workspaces.filter(\.hasBarOccupancy)` runs *before* `activeWorkspaceId` is computed (`Sources/Nehir/UI/WorkspaceBar/WorkspaceBarDataSource.swift:151-155`), so navigating to an empty workspace with Hide Empty Workspaces on leaves no item with `isFocused == true` (`:190`). The foreign-display path has the same hole (`:221`). | **🔴** | XS | `WorkspaceBarDataSource.swift` |
| `100586d2` + `d5df958d` Recover multitouch devices across lifecycle changes | Verified startup, callback generations, bounded retries, CoreHID topology observer, unlock revalidation. | **Partial — sleep/wake only, with a confirmed silent-deafness path.** See sub-finding. | **🔴** (port the intent, not the 740-line diff) | M | `Sources/Nehir/Core/Multitouch/MultitouchGestureSource.swift`, `MultitouchBinding.swift`, `MouseEventHandler.swift`, `ServiceLifecycleManager.swift` |
| `28a17e22` Add system window corner controls and border geometry | Corrected SkyLight corner-radii symbol signature, per-corner radii with retry, global corner-radius settings UI. | **Decomposes — see sub-findings.** Nehir's `BorderManager` is the 1:1 counterpart of upstream's `BorderSurfaceApplier` and carries the pre-fix shape (`Sources/Nehir/Core/Border/BorderManager.swift:22-34`, `:81-118`, `:149-158`). `noop/20260617-omniwm-362-border-corner-radius.md` owns "border radius matches real window radius" and remains correct — this commit goes beyond it. | **🟡** (2 of 4 sub-items) | S–M | `Sources/Nehir/Core/SkyLight/SkyLight.swift`, `BorderManager.swift`, `BorderWindow.swift` |
| `6d0dd894` Move running-app inventory into Core | Core owns regular-app discovery, merging tracked-window overlays with `NSWorkspace.runningApplications`. | **Behaviour gap + architectural fit.** Nehir's "Pick from running apps" list is built only from admitted, standard-layout managed entries (`Sources/Nehir/Core/Controller/WindowActionHandler.swift:801-825`, consumed at `Sources/Nehir/UI/AppRulesView.swift:496-520`), so a running app with no managed window — precisely the app you most need a rule for — cannot be picked; it also drops apps with no cached bundle id and sorts by raw `<`. The Core extraction lines up with `discovery/20260702-mega-file-growth-and-narrow-wmcontroller-revisit.md`. | **🟡** | S | `WindowActionHandler.swift`, new `Sources/Nehir/Core/Controller/RunningAppInventory.swift`, `AppRulesView.swift` |
| `436cff3f` Hug the measured width when centring the bar island | Size the centred panel to measured content instead of a 300pt floor. | **Pre-fix constant present; symptom unconfirmed.** `let width = max(fittingWidth, 300)` (`Sources/Nehir/UI/WorkspaceBar/WorkspaceBarGeometry.swift:39`). Whether the visible offset manifests depends on how the `NSHostingView` (`sizingOptions = []`, `WorkspaceBarManager.swift:508-511`) aligns the root `HStack` inside an oversized panel — **not verifiable statically**. The panel over-covering ~300pt of menu-bar strip it never draws on is true regardless. | **🟡** (visual repro) | XS | `WorkspaceBarGeometry.swift` |
| `cc622f22` Add app-provided workspace bar icon overrides (BarutSRB/OmniWM#495) | Discover icon variants inside app bundles; user picks one or a custom image. | **Absent.** Bar icons come straight from `AppInfoCache` (`Sources/Nehir/Core/AppInfoCache.swift:11`) via `createWindowItems` (`WorkspaceBarDataSource.swift:169-184`). Large net-new surface. Should reuse the app-rule seam chosen in `planned/20260621-omniwm-311-exclude-apps-from-workspace-bar.md`, **not** upstream's global bundle-id list. | **🟡** (product decision) | L | `WorkspaceBarDataSource.swift`, `SettingsStore.swift`, `CanonicalTOMLConfig.swift`, new UI |
| `e16ce80b` Add rich help for status menu controls | Hover/keyboard-focus help cards with animated previews. | **Absent, not diff-portable.** Nehir's status menu is an AppKit `NSMenu` of `NSMenuItem`s with custom views (`Sources/Nehir/UI/StatusBar/StatusBarMenu.swift:50-53`, `:109-165`), not upstream's SwiftUI `StatusMenuView`; no `toolTip`s either. A port is a Nehir-native design exercise (opus-owned UI). `NSMenuItem.toolTip` on the toggle rows is the XS subset if only discoverability is wanted. | **🟡** (design decision) | XS / L | `StatusBarMenu.swift` |
| `46de1498` Remove macOS reduced motion support | Stop consulting `accessibilityDisplayShouldReduceMotion`. | **Decomposes — do not follow wholesale.** The dead scaffolding upstream deletes is dead in Nehir too (`SpringConfig.reducedMotion` unused alias and identity no-op `resolvedForReduceMotion`, `Sources/Nehir/Core/Animation/SpringAnimation.swift:81-86`, called with a hard-coded `false` at `:123`). But Nehir's **live** honoring is real behaviour: appear/close offset scaling (`Sources/Nehir/Core/Controller/NiriLayoutHandler.swift:1030-1031`, `Sources/Nehir/Core/Controller/LayoutRefreshController.swift:373-374`) and bar animation gating (`Sources/Nehir/UI/WorkspaceBar/WorkspaceBarView.swift:282`, `:329`). Removing those is an accessibility regression with no Nehir-side justification. | **🟢** (skip the removal) / **🟡** (XS dead-code cleanup) | XS | `SpringAnimation.swift` |
| `1f9576f0` Fix workspace bar click on emoji-named workspaces (PR BarutSRB/OmniWM#478) | Route bar pill clicks through workspace id instead of display name. | **Already have — Nehir is the origin.** `focusWorkspaceFromBar(id:)` end to end (`Sources/Nehir/Core/Controller/WMController.swift:784-786`, `WindowActionHandler.swift:708-716`, `WorkspaceManager.swift:2491-2497`), bar wiring passes `item.id` (`Sources/Nehir/UI/WorkspaceBar/WorkspaceBarManager.swift:662`); the label is a separate `displayName(for:)` projection (`WorkspaceBarDataSource.swift:188-189`). | **🟢** (closes the prior sweep's 🟡) | — | none |
| `e2e661b4` Deduplicate workspace bar focus transition | Collapse named/id bar-focus paths onto one shared completion. | **Already have,** and richer: the shared private `focusWorkspaceFromBar(result:suppressMouseWarp:)` (`WindowActionHandler.swift:718-746`) plus `focusWorkspace(named:)` delegating to `focusWorkspace(id:)` (`WorkspaceManager.swift:2485-2489`), with viewport-state save and mouse-warp suppression upstream lacks. | **🟢** | — | none |
| `49c22c03` Focus workspaces from the whole bar item | Give the item container a hit shape matching the drawn pill. | **Already have.** `.contentShape(Rectangle())` + `.onTapGesture` on the whole padded item (`Sources/Nehir/UI/WorkspaceBar/WorkspaceBarView.swift:609-612`); child `Button`s keep priority (`:651`, `:750`). Cosmetic nit: Nehir uses `Rectangle()` where upstream uses `RoundedRectangle(cornerRadius:)`, so the hit area includes four corner squares outside the visible pill. | **🟢** (optional XS polish) | XS | `WorkspaceBarView.swift` |
| `8eaaa42a` Refresh diagnostics after hotkey updates (BarutSRB/OmniWM#490) | Recompute the diagnostics issue list inside the hotkey-update path. | **Already have, different mechanism.** Nehir recomputes from the *observable* side: `SettingsSidebar` refreshes `.onChange(of: settings.hotkeyBindings)` (`Sources/Nehir/UI/SettingsSidebar.swift:46-53`, `:75-83`), same in `DisplayDiagnosticsSettingsTab.swift:285`; menus build lists on demand. No cached controller-side list exists to go stale. | **🟢** | — | none |

### Lane 4 sub-findings

**Multitouch — the silent-deafness path (🔴).** Nehir *does* stop on sleep and
restart on wake (`Sources/Nehir/Core/Controller/ServiceLifecycleManager.swift:526-552`
→ `MouseEventHandler.restartMultitouch()`, `MouseEventHandler.swift:350-353`), which
is better than upstream's pre-fix state. The remaining gaps are real:

1. **`start()` reports success on a zero-device enumeration.** It guards only on
   `binding.devices()` returning `nil`; a non-`nil` list with **zero** refs registers
   nothing and sets `isRunning = true` anyway
   (`Sources/Nehir/Core/Multitouch/MultitouchGestureSource.swift:47-58`). The source
   then looks healthy, `restart()` is never called again, and no gesture fires until
   the next sleep/wake cycle. Because the wake handler fires `restartMultitouch()`
   **immediately** on `NSWorkspace.didWakeNotification` (`ServiceLifecycleManager.swift:541-552`),
   this is exactly the window in which `MTDeviceCreateList` is most likely to come
   back empty. No retry exists anywhere. Strong candidate root cause for intermittent
   "four-finger swipe stopped working" reports (Nehir #53; see
   `discovery/20260618-raw-multitouch-gesture-source.md`, which already flags that the
   wake observer does not re-arm the *gesture tap* either).
2. **Start status is discarded.** `MTDeviceStart` is typed `(DeviceRef, Int32) -> Void`
   and `MTRegisterContactFrameCallback` returns `Void`
   (`Sources/Nehir/Core/Multitouch/MultitouchBinding.swift:22-25`, `:73-85`), so a
   failed start is indistinguishable from a successful one; there is no
   `MTDeviceIsRunning` equivalent.
3. **No device arrival/removal handling.** Devices are enumerated exactly once per
   `start()`; a trackpad connected after startup never registers, and `stop()`
   unregisters possibly-dangling refs captured at start (`:60-70`).
4. **Unlock does not revalidate.** `handleUnlockDetected()` refreshes layout only
   (`ServiceLifecycleManager.swift:389-392`).
5. **Not reproduced at runtime.** Land a diagnostic counter ("enumerated 0 devices
   while marking running") **first**, so the fix is falsifiable rather than assumed.

Recommended shape (not a diff apply): make `start()` fail on zero registrations; add
a bounded retry with backoff behind a single coalesced revalidate entry point
(`wake` / `unlock` / `arrival`); have the binding surface `MTDeviceStart`'s status and
an `MTDeviceIsRunning` probe so startup is *verified*; expose a small diagnostics
snapshot through the existing input diagnostics. The CoreHID digitizer-usage matching
from `d5df958d` is the optional last mile.

**`28a17e22` — window corners, four ways.**

1. **Missing-sample retry / sticky default radius — 🟡 leaning 🔴, S.**
   `resolvedCornerRadius` caches per `windowId` and falls back to
   `defaultCornerRadius = 9.0` whenever the SkyLight query returns `nil`
   (`Sources/Nehir/Core/Border/BorderManager.swift:149-158`). The cache is cleared
   only on apply failure or hide (`:109`, `:160-167`), so a query returning nothing
   because the window's surface is not yet composited **pins a wrong 9.0 radius for
   as long as that window stays focused**. Upstream's `needsCornerRadiiRetry` exists
   for exactly this. Visible as a border whose corners disagree with square-cornered
   or large-radius windows right after focus.
2. **SkyLight symbol signature mismatch — 🟡, XS, verify first.** Nehir declares
   `SLSWindowIteratorGetCornerRadii` as `@convention(c) (CFTypeRef) -> CFArray?`
   (`Sources/Nehir/Core/SkyLight/SkyLight.swift:30`) and consumes it unowned
   (`:432-445`); upstream's corrected declaration is
   `(CFTypeRef, CFIndex) -> Unmanaged<CFArray>?` with `takeRetainedValue()`. If
   upstream is right, Nehir passes an undefined second-argument register as the index
   and leaks a `CFArray` on every corner query — which runs on every border update
   for a newly focused window. **Not confirmed**: this is a private-API ABI claim
   resting on upstream's declaration. Verify with a leaks/allocation run before
   changing anything.
3. **Per-corner radii / resolved-vs-raw sampling — 🟡, S–M.** Nehir reads only index 0
   as a uniform `Int32` (`SkyLight.swift:427-445`) and draws one uniform radius
   (`Sources/Nehir/Core/Border/BorderWindow.swift:203-213`, which already does the
   correct `outerRadius = cornerRadius + borderWidth`). Worth doing only if a real
   window with asymmetric corners is observed.
4. **Global window corner-radius settings UI — 🟢 skip.** Upstream's
   `GlobalWindowCornerPreferences` writes `NSGlobalDomain` corner-radius keys via
   `CFPreferencesSetMultiple(..., kCFPreferencesAnyApplication, ...)` — a
   **system-wide** macOS mutation affecting every app. Recommend not porting without
   an explicit product call.

---

## Lane 5A — monitor identity, per-display config, settings surface

| Upstream commit | One-line change | Nehir-equivalent already present? (file:line) | Verdict | Effort | Nehir files |
| --- | --- | --- | --- | --- | --- |
| `92381816` Persist stable monitor identities across display changes (Fixes BarutSRB/OmniWM#472, Refs BarutSRB/OmniWM#278) | Adopt CoreGraphics display UUIDs as durable identity for per-monitor settings, routing, workspace assignments and restore; keep `CGDirectDisplayID` session-local; fail closed on ambiguity. | **No display-UUID identity anywhere.** `Monitor` carries only `id`/`displayId`/`frame`/`visibleFrame`/`hasNotch`/`name` (`Sources/Nehir/Core/Monitor/Monitor.swift:10-45`); Nehir instead built a name + anchor-point heuristic (`Sources/Nehir/Core/Config/MonitorSettingsType.swift:78-129`) plus an `ignoreMonitorIdentity` position mode (`completed/20260630-monitor-override-identity-and-inactive-ui.md`, `completed/20260618-monitor-identity-agnostic-restore.md`). Mixed picture with one confirmed residual bug. | **🟡 overall, 🔴 sub-finding** | M (sub-finding S) | `OutputId.swift`, `MonitorRestoreAssignments.swift`, `Monitor.swift`, `SkyLight.swift`, `MonitorSettingsType.swift` |
| `c35974fe` per-display inner gap overrides (PR BarutSRB/OmniWM#477) | Add an inner-gap override to per-display gap settings; surface it in settings UI, IPC `displays` query, automation manifest and CLI. | **Settings model: yes.** `MonitorGapSettings` already carries `gapSize` alongside the four outer gaps as a per-display `MonitorSettingsType` (`Sources/Nehir/Core/Config/MonitorGapSettings.swift:23-36`), persisted via `monitors.d/*.toml` (`MonitorOverrideFileStore.swift:36-51`). **IPC/CLI: no.** `IPCDisplayQuerySnapshot` has `id/name/isMain/isCurrent/frame/visibleFrame/hasNotch/orientation/activeWorkspace` and **no gap fields at all** (`Sources/NehirIPC/IPCModels.swift:2353-2383`); the automation manifest's display field list stops at `orientation` (`Sources/NehirIPC/IPCAutomationManifest.swift:319-321`). Nehir is missing all five. **This corrects the previous sweep's flat 🟢.** | **🟡** (IPC/CLI parity gap) | XS–S | `IPCModels.swift`, `IPCAutomationManifest.swift`, `Sources/NehirCtl/CLIRenderer.swift`, IPC query router |
| `18e6925a` fix(cli): format whole gap values cleanly | Render `8.0` as `8` in the CLI gap columns. | **N/A until the gap columns exist.** Fold the integer-formatting rule into the parity work above. | **🟢** (fold-in) | XS | `CLIRenderer.swift` |
| `1fd5f6ee` feat(monitors): guided multi-monitor setup | One-time replayable setup assistant, display-identification overlay, persisted onboarding status, hot-plug re-evaluation, and a monitor-topology refresh before services start. | **Onboarding exists but has no monitor step.** Nehir has its own wizard (`Sources/Nehir/UI/Onboarding/OnboardingSteps.swift`) gated by a version store (`Sources/Nehir/Core/Config/OnboardingStateStore.swift:20-50`) and a Monitor settings tab with warp axis/order (`Sources/Nehir/UI/MonitorSettingsTab.swift:52-95`), but no guided assistant, no identification overlay, no persisted monitor-setup status. | **🟡** (product decision; opus-owned UI) | L | `MonitorSettingsTab.swift`, `Sources/Nehir/UI/Onboarding/*`, `SettingsStore.swift` |

### Lane 5A sub-findings

**🔴 Recycled-`displayId` short-circuit still live in workspace pins and restore — S.**
`completed/20260630-monitor-override-identity-and-inactive-ui.md` fixed exactly this
hazard ("display IDs are runtime handles and can be reused by a different physical
display") for `MonitorSettingsType`, which now disambiguates a reused handle via name
+ anchor (`Sources/Nehir/Core/Config/MonitorSettingsType.swift:89-105`). **The same
fix was never propagated to the other two resolvers:**

- `Sources/Nehir/Core/Monitor/OutputId.swift:32-35` — `resolveMonitor` returns the
  first monitor whose `displayId` matches and **never checks `name`**. `OutputId` is
  the persisted workspace→display pin (`MonitorDescription.output`,
  `Sources/Nehir/Core/Monitor/MonitorDescription.swift:26-27`), so a workspace pinned
  to a now-disconnected monitor silently rebinds to whatever unrelated display
  currently holds that handle.
- `Sources/Nehir/Core/Monitor/MonitorRestoreAssignments.swift:66-72` — the identity
  pass assigns on `$0.displayId == snapshot.monitor.displayId` alone, ignoring the
  `name` and `frameSize` it already stores in `MonitorRestoreKey` (`:10-22`).

Nehir does not need a UUID to close this: requiring `Monitor.namesMatch` (or the
stored anchor) on the `displayId` branch is enough and matches the shipped precedent.
**Plan it on its own; it is a correctness bug independent of any UUID adoption.**

**🟡 Display UUID as durable identity — M.** The primitive already exists in-tree but
is private and used for something else: `CGDisplayCreateUUIDFromDisplayID` is
dlsym-loaded at `Sources/Nehir/Core/SkyLight/SkyLight.swift:163-168` and consumed only
by `managedDisplayIdentifier(for:)` (`:528-533`) to key SkyLight managed-display
dictionaries. Promoting it to `Monitor.displayUUID` and preferring it in `OutputId` /
`MonitorSettingsType` / `MonitorRestoreKey` would make identity genuinely stable
across reconnects, ports and rearrangement — **M-sized, not L**, because the primitive
is already there. **Caveat:** it must be designed *around*, not against, Nehir's
deliberate `ignoreMonitorIdentity` position mode
(`Sources/Nehir/UI/MonitorSettingsTab.swift:57`, threaded through
`RestorePlanner.swift:163,283` and `MonitorRestoreAssignments.swift:39`), which
upstream does not have. A UUID identity strengthens the identity-on path; it must not
short-circuit the identity-off path.

**🟢 Two upstream sub-changes Nehir already shipped.** "Avoid topology-driven settings
rewrites" — already identified and fixed
(`completed/20260630-monitor-override-identity-and-inactive-ui.md`, section
"Load-time rebinding mutates persisted override identity"). Ambiguity fail-closed
policy — already present in Nehir's resolvers (`MonitorSettingsType.swift:96-100`,
`:198-200`; `OutputId.swift:46-48`); only the `displayId` branches above are not.

**🟡 Monitor topology refresh before services start — XS–S, verify.** Upstream added
`refreshMonitorConfigurationForServiceStart(currentMonitors:)` at the top of
`startServices()`. Nehir's `startServices()` does no such refresh — it goes straight
to `hasStartedServices = true`
(`Sources/Nehir/Core/Controller/ServiceLifecycleManager.swift:77-79`) and only
refreshes on later display notifications (`:198-224`, `:425-435`). Since service start
is gated behind the accessibility-permission grant loop (`:56`, `:67`), the window
between monitor capture and service start can be long (user in System Settings,
plugging in a display). **Not confirmed to misbehave**, but the guard is cheap and the
seam is identical.

---

## Lane 5B — upstream issue / PR sweep (updated since 2026-07-13)

`gh issue list -R BarutSRB/OmniWM --state all --search "updated:>=2026-07-13"`
(41 issues) plus the matching PR list (14 PRs). Rows deep-triaged by another lane are
given status only and cross-referenced.

| Upstream issue / PR | Status | Coverage / Nehir applicability | Verdict |
| --- | --- | --- | --- |
| BarutSRB/OmniWM#474 directional hotkeys inverted on vertical monitors | **now closed** (2026-07-27) | Closed by `12f8ee43` + `f54b28d6` + `4504522d`. Deep triage in Lane 2 — closes on **O1+O2**, XS behind one portrait repro. | **🔴** (Lane 2) |
| BarutSRB/OmniWM#467 certain windows not picked up | **now closed** (2026-07-17) | Closed by the five-commit 0.5.7 admission cluster. Nehir has admission recovery + omission diagnostics (`Sources/Nehir/Core/Ax/AXManager.swift:578-629`, `Sources/Nehir/Core/Controller/AXEventHandler.swift:4278-4357`); the cluster is large and touches Nehir's most-diverged subsystem. Upgrade from "monitor" to "scoped comparison worth its own lane". | **🟡** |
| BarutSRB/OmniWM#511 / BarutSRB/OmniWM#508 no-fullscreen-button windows not managed | **now closed** (2026-07-26) | Closed by `7ea45238`. Lane 1 confirmed the predicate defect in Nehir — **L1-E**. | **🔴** |
| BarutSRB/OmniWM#505 Chrome WebApps closed when enabling | **now closed** (2026-07-24) | Closed by `a4b8611a`. Lane 1 confirmed Nehir carries the pre-fix event record. | **🔴** |
| BarutSRB/OmniWM#488 / BarutSRB/OmniWM#489 move up/down doesn't honour Follow Window | **now closed** (2026-07-17) | Closed by `b35d39d4` + `6d516923`. Lane 3 confirmed three of five Nehir paths ignore the setting. | **🔴** |
| BarutSRB/OmniWM#498 / BarutSRB/OmniWM#499 Niri does not recenter after closing the last pane | **now closed** (2026-07-21) | Closed by `a91f20e8` / `53901835`. Lane 2 confirmed this is a **different defect** from Nehir's existing close-recovery docs. | **🔴** |
| BarutSRB/OmniWM#487 fullscreen apps stuck after quit | **now closed** (2026-07-27) | Closed by `044441c4`. Lane 2 confirmed the evidence loss at Nehir's `PreparedDestroy` boundary. | **🔴** |
| BarutSRB/OmniWM#509 / BarutSRB/OmniWM#510 Focus Previous uses stale selection | **now closed** (2026-07-27) | Closed by `2a7041d8`. Lane 3 confirmed both halves absent in Nehir. | **🔴** / 🟡 |
| BarutSRB/OmniWM#493, BarutSRB/OmniWM#486 gestures / Magic Trackpad not working | **now closed** | Closed by `100586d2` + `d5df958d`. Lane 4 confirmed Nehir's silent-deafness path. | **🔴** |
| BarutSRB/OmniWM#503 / BarutSRB/OmniWM#504, BarutSRB/OmniWM#501 / BarutSRB/OmniWM#502, BarutSRB/OmniWM#122 bar centring / hit area | **now closed** | Closed by `ac0a0287`, `436cff3f`, `49c22c03`. Lane 4: `ac0a0287` **🔴 XS**, `436cff3f` 🟡 verify, `49c22c03` 🟢. | mixed |
| BarutSRB/OmniWM#482 allow moving workspaces between monitors | **now closed** (2026-07-27) | Closed by `9babdb12` + `a5064c50`. Nehir owns this as `planned/20260619-nehir-62-move-workspace-to-monitor.md` — **which Lane 3 found is contradicted on its central mechanism**. | **🟡** (revise the plan) |
| BarutSRB/OmniWM#490 "Hotkey May Conflict" never goes away | **now closed** (2026-07-23) | Closed by `8eaaa42a`. Lane 4: Nehir refreshes from the observable side — 🟢. Residual XS verify: does Nehir's advisory actually clear after a rebind? | **🟢** / 🟡 verify |
| BarutSRB/OmniWM#518 Terminal.app cannot be stacked in a Niri column since 0.5.7 | **open** | **Nehir is architecturally on the correct side and should not port `348232a0`.** Upstream's frame-refusal quarantine broke character-cell apps. Nehir has no quarantine (grep `quarantin` over `Sources/Nehir` is empty) and instead classifies cell quantization as bidirectional overshoot, accepts the snapped frame, and deliberately records no inferred minimum (`Sources/Nehir/Core/Controller/LayoutRefreshController.swift:4139-4188`, the comment names Ghostty). **Residual risk worth verifying:** after 3 consecutive frozen shrink refusals Nehir escalates to a hard inferred minimum (`:4177`, threshold at `:226`), which in a deep column stack (height/N) could over-constrain a Terminal-like app. Not reproduced. | **🟢** for the port / **🟡** verify the streak threshold |
| BarutSRB/OmniWM#468 FFM no longer traverses to off-screen columns | **closed NOT_PLANNED** (2026-07-13) | Upstream **declined** it — there is no landed fix to match. Nehir's FFM still requires the pointer inside a rendered frame (`Sources/Nehir/Core/Layout/Niri/NiriLayoutEngine+InteractiveResize.swift:65-92`). The previous sweep's "verify against the upstream fix" is void. | **🟡 → Nehir product decision** |
| BarutSRB/OmniWM#507 FFM focuses a partially-visible window without revealing it | **open** | The **inverse** request to BarutSRB/OmniWM#468, from a different user. Together they show upstream has **no settled contract** on FFM reveal policy. This makes it a genuine Nehir design question, not a port. | **🟡** (design decision) |
| BarutSRB/OmniWM#491 Omni chooses its own main monitor | **open** | Nehir's `Monitor.isMain` prefers `CGMainDisplayID()` and only falls back to origin/frame heuristics when it returns 0 (`Sources/Nehir/Core/Monitor/Monitor.swift:75-87`), so the naive form is unlikely. Nehir already owns the same symptom class in `planned/20260714-internal-display-new-window-placement.md` and `completed/20260713-finder-focused-admission-frame-monitor-snaps-to-internal-display.md`. No upstream fix landed. | **🟡** (folds into the existing plan; no new doc) |
| BarutSRB/OmniWM#496 Dock terminated or hidden after closing OmniWM | **open** | Nehir **only reads** the Dock preference — `CFPreferencesCopyAppValue("autohide", "com.apple.dock")` (`Sources/Nehir/Core/Monitor/Monitor.swift:237-239`); there is no write anywhere in `Sources/Nehir`, so the "it changed my Dock settings" form does not apply. The plausible Nehir analogue is a leftover dock-edge shield surface after shutdown. | **🟡** (verify shutdown surface teardown) |
| BarutSRB/OmniWM#517 System Settings sub-window loses focus on reopen | **open** | Focus-restoration class; adjacent to `3419f4fe` but no upstream fix landed. Not verified against Nehir source. | **🟡** (needs a Nehir repro) |
| BarutSRB/OmniWM#480 window sizes stuck at ultrawide proportions after disconnect | **closed** (2026-07-25) | Monitor-topology class. Nehir stores Niri column widths as proportions and re-resolves per monitor, but this was **not verified in depth**. Related Nehir topology-bounce/repark docs exist. | **🟡** (unverified — needs its own check) |
| BarutSRB/OmniWM#472 `singleWindowAspectRatio` / `column_width` no effect | **closed** (2026-07-24) | Closed by `92381816`. Upstream's root cause was a **stale per-monitor Niri override shadowing global single-window sizing** — the same concrete bug Nehir already reproduced and fixed on `main` as `4120e545` (`completed/20260630-monitor-override-identity-and-inactive-ui.md` inlines the numbers: a disconnected `DELL P2423D` override with `loneWindowMaxWidth=0.6` applied on a built-in display). Verdict unchanged, now better-evidenced. | **🟢** |
| BarutSRB/OmniWM#483 ghost window after closing Chrome tab | **closed** (2026-07-27) | Closed by `780cf917`; Lane 1 confirmed Nehir has the equivalent, arrived independently and earlier. | **🟢** |
| BarutSRB/OmniWM#495 workspace bar per-app icon override | **closed** (2026-07-26) | Closed by `cc622f22`. Net-new bar feature — see Lane 4. | **🟡** (feature) |
| BarutSRB/OmniWM#506 Niri scroll axis customisation | **closed** (2026-07-25) | Part of the orientation cluster — Lane 2 **O5**. | **🔴** (Lane 2) |
| BarutSRB/OmniWM#454 won't launch on v0.5.3.2 | **closed** (2026-07-14) | Upstream-specific launch/dependency issue; Nehir has no FoundationModels dependency. | **🟢** |
| BarutSRB/OmniWM#515 / BarutSRB/OmniWM#516 Dwindle vertical move; BarutSRB/OmniWM#513 quake blur; Ghostty glass | closed / merged | **N/A** — Nehir is Niri-only with no embedded Quake/Ghostty terminal (standing strategic divergence). | **🟢** |
| BarutSRB/OmniWM#470 tabbing in command palette; BarutSRB/OmniWM#520, BarutSRB/OmniWM#246, BarutSRB/OmniWM#481 | open / closed | Nehir's palette has a different interaction model; the rest are support/triage items with no landed behavioural fix relevant to Nehir. | **🟢** |

### Carried open items from prior sweeps — status at `f9aff475`

- **`679f0ba3` scroll-animation frame-echo guard — now substantially landed;
  downgrade and close after one check.** `Sources/Nehir/Core/Controller/AXEventHandler.swift:1706-1709`
  returns early from the geometry-changed relayout path when
  `niriLayoutHandler.hasScrollAnimation(for:)` is true (counter
  `geometryRelayoutsSuppressedDuringGesture`); the same guard appears at
  `LayoutRefreshController.swift:4410` and `MouseEventHandler.swift:937`. **Not
  confirmed** that the guard sits ahead of every expensive window-server query in that
  path — upstream's specific framing. Re-verify the query ordering, then close rather
  than plan a port.
- **`25f4a459` transient-subrole floating seed guard — still open (🔴, S).**
  `WMController.seedFloatingGeometryIfNeeded` (`Sources/Nehir/Core/Controller/WMController.swift:1919-1941`)
  still seeds `restoreToFloating: true` from the live frame with no
  missing-fullscreen-button / non-standard-subrole exclusion. `7ea45238` is a second,
  newer upstream reference for the same family.
- **`6520c461` no-op readmission guard — still open (🟡, M).** No
  `shouldReadmitTrackedWindow` helper exists; the rescan path still computes
  `structuralReplacementWorkspaceId` and can re-add
  (`Sources/Nehir/Core/Controller/LayoutRefreshController.swift:1510-1542`).
- **`9abda3d2` durable title cache — still open (🔴, XS).** `AXWindow` still uses a
  0.5 s TTL (`Sources/Nehir/Core/Ax/AXWindow.swift:287`, checked at `:295-299`), so
  workspace-bar reconciles re-query titles on the hot path.
- **BarutSRB/OmniWM#440 overlay-tool exclusion — still open upstream and unaddressed
  in Nehir (🔴).** `Sources/Nehir/Core/Config/WindowCapabilityProfile.swift` remains
  the suggested seam. Note upstream **deleted** that file in `7dbe8f30` as part of the
  WorldStore rewrite Nehir never adopted, so the seam is Nehir-only going forward.
- **`689974b5` "Track system modal focus separately" (2026-06-15) — untriaged,
  predates this sweep's cutoff.** Surfaced as a blocking dependency for `3419f4fe`.
  Carry it into the next sweep.

The previous sweep's 🔴 recommendations now have plans on this branch:
`planned/20260714-reinstall-ax-observers-after-service-restart.md` (unmerged),
`planned/20260714-omniwm-457-directional-monitor-axis-dominance.md`,
`planned/20260714-omniwm-446-cursor-inside-no-warp-guard.md`.

---

## Recommendation — what to plan next

Ranked by confidence × leverage. Everything in tier 1 has a source-cited pre-fix
shape in `main` and is XS–S.

**Tier 1 — small, confirmed, independent**

1. **~~🔴~~ 🟡 `a4b8611a` SkyLight key-window event record (XS) — shipped as hardening.**
   Nehir carries the byte-for-byte pre-fix record on its primary focus path
   (`Sources/Nehir/Core/PrivateAPIs.swift:38-58`, reached from `WMController.swift:43`).
   Pad the buffer to `0x100`, declare length `0xF8`, write a finite `(-1,-1)` instead
   of the `0x20..<0x30` NaN block.
   **Erratum (2026-07-28, runtime).** This was ranked "highest confidence in the
   sweep" on static reading alone. The symptom is **not reproducible** — not on
   Nehir `main` without the port, and not on upstream OmniWM v0.5.7 itself, on the
   reporter's own macOS build. The upstream issue has zero comments and no
   diagnosis. Implemented on `patch/skylight-key-window-event-record` as hardening
   with no release note; do not describe it as fixing an observable defect. Detail
   and the generalisable lesson:
   [`20260728-skylight-key-window-nan-location-symptom-not-reproducible.md`](20260728-skylight-key-window-nan-location-symptom-not-reproducible.md).
2. **🔴 `ac0a0287` Hide Empty Workspaces drops the focused workspace (XS).** Filter on
   `hasBarOccupancy || id == activeWorkspaceId` at
   `Sources/Nehir/UI/WorkspaceBar/WorkspaceBarDataSource.swift:151-155`, and decide
   the same question for the foreign-pill path (`:221`), which upstream does not have.
3. **🔴 Consolidate the workspace-move focus handoff (S).** One `finishWorkspaceMove`
   helper reading `focusFollowsWindowToMonitor`, five call sites, one behaviour test
   suite — fixes a user-visible setting that silently does nothing on three of five
   paths, closes the `stopScrollAnimation` asymmetry, and lands the cheap staleness
   guards from `ea490f8e` + the `e75bc2a5` recompute-half in the same edit.
4. **🔴 `a91f20e8` removal-time viewport clamp (S).** Start with the S-sized shape
   (clamp settled view origin to the surviving content edge at the single
   `removeWindows` choke point); treat `53901835` as the follow-up adding
   column-removal gating and the coalescing seam. **Do not copy `53901835`'s
   centering-policy block verbatim** — rewrite it against Nehir's reveal-style model,
   sequenced with the width-cycle recentering work.
5. **🔴 Recycled-`displayId` guard in `OutputId.resolveMonitor` and
   `resolveWorkspaceRestoreAssignments` (S).** Require name/anchor corroboration on
   the `displayId` branch, matching the shipped `MonitorSettingsType` precedent.
   Independent of any UUID adoption.
6. **🔴 Finish `planned/20260714-reinstall-ax-observers-after-service-restart.md`.**
   Re-verified as still open; pair the low-risk `RunLoopJob` serialization port with it.

**Tier 2 — confirmed but gated on a repro or a decision**

7. **🔴 O1+O2 orientation-aware directional focus (XS code, gated on one portrait
   repro).** Pass `orientation` at `NiriLayoutHandler.swift:1521` and `:1736`, resolve
   `cachedHeight` on the vertical branch — but settle the
   `Direction.primaryStep(for: .vertical)` sign first, or the change inverts focus
   instead of fixing it. Closes BarutSRB/OmniWM#474. Bundle with **O4** (vertical
   container move animation, self-contained in `NiriNode`) as "make portrait usable,
   phase 1"; **O5** (gesture axis) is phase 2.
8. **🔴 Multitouch lifecycle recovery (M).** Land the diagnostic counter
   ("enumerated 0 devices while marking running") **first** so the fix is falsifiable,
   then verified startup + bounded coalesced retry + arrival/unlock revalidation.
   Plausible root cause for Nehir #53.
9. **🔴 L1-E attribute-evidence predicate (XS) — land it with the `3f3d2fb9`
   classification fixture corpus (M).** The one-line predicate tightening shifts
   classification for *every* window, so the fixture corpus is a prerequisite, not a
   nice-to-have. Fold in L1-F (absent-vs-failed) as the same change.
10. **🔴 `044441c4` destroy-evidence preservation (M).** Add the origin to
    `PreparedDestroy`, gate `handleNativeFullscreenDestroy` on transient evidence, let
    a definitive close upgrade a queued transient destroy. Well-fenced to
    `AXEventHandler.swift`; composes with the planned VS Code create-side rekey work.
11. **🔴 `7f300c31`(a) stop focusing on cancelled/aborted gestures (S).** Reduces the
    blast radius of the open fling-snap-overshoot discovery. Confirm with a repro
    (swipe interrupted by a fourth finger or a display change) first.
12. **🔴 L1-D AX observer incarnation re-subscription (S).** Gate on a repro or a unit
    test through `installSubscribedWindowsForTests`.
13. **🔴 `2a7041d8` Focus Previous anchor from observed frontmost (S).** The only item
    that partially mitigates the stuck-focus cluster's user-visible symptoms.

**Tier 3 — revise existing plans before delegating**

14. **Revise `planned/20260619-nehir-62-move-workspace-to-monitor.md`.** Its mechanism
    is refuted by `WorkspaceManager.swift:4301-4309` and by Nehir's own test at
    `Tests/NehirTests/WorkspaceManagerTests.swift:900-928`; delegating it as written
    produces a command that no-ops for home-monitor users. Adopt `9babdb12`'s
    runtime-override + `force` model, keep Nehir's cyclic UX. S to revise, L to build.
15. **Amend `planned/20260621-omniwm-283-per-app-initial-column-width.md`** to define
    the app-rule field as an orientation-relative *initial container primary span*.
    Free now, expensive later (persisted-key migration).
    `planned/20260621-omniwm-295-niri-window-width-preservation.md` needs no change.

**Tier 4 — cheap parity and verify-first**

16. 🟡 IPC/CLI gap parity for `displays` (XS–S, purely additive to the wire model).
17. 🟡 Batch of XS verifies: border corner-radius retry (`BorderManager.swift:149-158`),
    hotkey-advisory clearing after rebind, Terminal-app streak escalation under column
    stacking (`LayoutRefreshController.swift:4177`), shutdown surface teardown,
    pre-service-start topology refresh, bar island centring, SkyLight corner-radii ABI.
18. 🟡 `6d0dd894` running-app picker (S) — real usability gap plus a clean extraction
    out of the `WindowActionHandler` mega-file.
19. 🟡 XS dead-code cleanup from `46de1498` — **but explicitly do not follow upstream in
    deleting Nehir's live reduce-motion handling**; that is an accessibility regression.

**Design decisions surfaced, not bugs:** FFM reveal policy (BarutSRB/OmniWM#468 and
BarutSRB/OmniWM#507 are opposite requests — upstream has no settled contract);
display-UUID durable identity; guided multi-monitor setup; O3 "Move Up/Down always
reorders within the container"; bar icon overrides; status-menu help cards;
confirmed-only focus MRU; staleness-gated post-layout focus completion.

**Explicitly not ported in this sweep:** the `WindowAdmission*` subsystem and
`AXWindowEnumeration` as such (Nehir's admission logic has diverged too far for a diff
apply — the value is in the extracted sub-findings); the terminal frame-refusal
quarantine `348232a0` (Nehir's inferred-minimum strategy is the deliberate
alternative, and upstream regressed on it — BarutSRB/OmniWM#518); `099f5b73` SkyLight
park reconciliation (Nehir's verified-AX park is further along); `61542a3c`
(no equivalent component); `58580ab5` Report Issue pipeline (no such feature yet);
the O7 `column`→`container` rename (an unmigrated hard break conflicting with Nehir's
config-migration policy); upstream's global `NSGlobalDomain` corner-radius mutation;
and all Dwindle / Quake / Ghostty-terminal work.

---

## Commits accounted for but not triaged

Verified by inspecting each diff, so the sweep is provably exhaustive over
`be68cfbf..044441c4`.

**Release / tooling** — `cdf5d380` Release 0.5.7, `d56d124f` Release 0.5.8,
`67e5312b` Release 0.5.9 (`Info.plist` bumps); `a640f0ba` SwiftFormat 0.62.1
(`Makefile`).

**Docs / marketing** — `7eb44c7f` trace files in `CONTRIBUTING.md`, `2f06251f` README,
`d2cbe18b` education contributor section, `e550aadc` Nix installation options,
`4f5fe074` contributor showcase and sponsor.

**Comment / fixture hygiene** — `f5e05a8c` remove non-header bar comments,
`6c574bf5` align Dwindle fix with comment policy, `46f1ab93` floating placement test
fixture.

**Merges with no unique content** — `859c6f50`, `366b0ff4`, `b57c64c6`, `20598c55`,
`65daf071`, `77d57474`, `ba3566dc` (0 files each). `6699b11f`, `f9cc1ee6`, `23faa10a`,
`b2a12b5d` carry only merged PR content already triaged under `6d516923`, `1f9576f0`,
`ea490f8e` and `c35974fe` respectively.

**Architecturally N/A — Nehir is Niri-only with no embedded terminal** — `fbff30cd`
Dwindle resize clamping, `4ca4d87b` inverted vertical Dwindle placement, `514bce36`
(Dwindle engine + tests only), `5efa8a88` quake terminal blur, `f5b87ebf` Ghostty
glass.

---

## Scope of this sweep vs. the loop

This doc accounts for upstream commits `be68cfbf..044441c4` (releases **0.5.7**,
**0.5.8**, **0.5.9** plus post-0.5.9) and upstream issues/PRs updated on or after
2026-07-13. **The running loop's next observation should resume from `044441c4`.**

Nothing here supersedes the canonical roadmap's deferred lanes. It adds twelve
source-confirmed 🔴 items — the largest yield of any sweep so far — restructures the
orientation port from "large feature" into six stageable slices, corrects two
verdicts the previous sweep recorded without verification (per-display gap IPC parity;
PR BarutSRB/OmniWM#478, now settled as Nehir-originated), and flags two existing plans
that must be revised before delegation. Several 🔴 items are explicitly gated on a
repro; those gates are stated per item and should not be dropped when the work is
planned.
