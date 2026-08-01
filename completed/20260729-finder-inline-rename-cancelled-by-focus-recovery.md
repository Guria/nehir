# Finder inline rename is cancelled by managed focus recovery

- **Nehir issue:** #179 — "[Bug] Unable to rename files or directories in Finder"; closed automatically when PR #193 merged on 2026-07-31.
- **Status:** completed — shipped on `main` in `90f47c04` ("Stop admitting non-window parented surfaces as managed windows"), merged 2026-07-31 via PR #193, contained in `v0.6.0-rc.43`. The user confirmed the Finder context-menu rename reproduction before merge. Moved from `discovery/` to `completed/` on 2026-08-01.
- **Reported on:** Nehir 0.6.0-rc.37 through rc.40; macOS 27 Public Beta 1; MacBook Air M1.
- **Original source baseline:** Nehir `main` at `38503d91`.
- **Workaround recorded in issue #179:** trigger rename with Return instead of the context-menu "Rename" item.

## Landed state

`WindowRuleEngine.presentsAsUserAddressableAXWindowSurface` is now the shared
predicate used by parented-surface admission and workspace-bar projection. A
parented surface whose AX fetch succeeded but whose role is not `AXWindow` is
classified by the built-in `nonWindowParentedSurface` rule as unmanaged. Failed
AX fetches retain the managed-floating fallback so unknown metadata is not
misread as proof that a real child window is non-standard.

This implements the discovery's first proposed change and was sufficient for
#179. The broader second proposal — suppressing every managed fronting operation
while an arbitrary same-application transient owns focus — did not ship in PR
#193; the shared surface predicate removes the causative layout refresh without
adding that wider focus policy.

The release note is
`.changeset/20260729134729-renaming-a-file-from-finder-s-context-menu-works.md`
with contributor `dagrlx`, the issue reporter. No dedicated Finder regression
test file landed; the change is covered by the shared rule path and the user's
confirmed context-menu reproduction. PR #193's CI ran `mise run test`
successfully (`Swift tests`, 3m38s) and passed `SwiftLint + SwiftFormat` (43s).

## Symptom

With Nehir running, choosing **Rename** from the Finder context menu does not
leave the item in an editable state. The inline rename text editor appears and is
dismissed, so the name cannot be typed. Renaming via the Return key works.

## Reproduction topology

Single built-in display, `displayId: 1`, `frame=(0.0, 0.0, 2056.0, 1329.0)`,
`visibleFrame=(0.0, 0.0, 2056.0, 1290.0)`, `isMain=true`, `hasNotch=true`. One
workspace active (`B08E3CE1-B4A2-450A-BB28-F60B7000AB3E`, displayed as workspace
1), 12 columns, `activeColumnIndex=1`. `displaySpacesMode=enabled`,
`focusFollowsMouse=false`.

Finder runs as `pid 85938`. Its browser window is `windowId 19001`, admitted as a
managed **tiling** window:

```
window_decision token=WindowToken(pid: 85938, windowId: 19001) context=focused_admission
  disposition=managed source=heuristic outcome=trackedTiling bundleId=com.apple.finder
  axRole=AXWindow axSubrole=AXStandardWindow hasCloseButton=true hasFullscreenButton=true
  fullscreenButtonEnabled=true hasZoomButton=true hasMinimizeButton=true
```

Steps: focus a Finder window, right-click an item, choose **Rename**.

## Observed event sequence

Timestamps below are from a single capture, all within the same second.

**1. The context menu makes focus non-managed.** Finder emits
`AXFocusedWindowChanged` with `window=nil` twice:

```
ax=AXFocusedWindowChanged pid=85938 window=nil
non_managed_fallback_entered pid=85938 source=focusedWindowChanged
non_managed_focus_changed active=true fullscreen=false preserve=false preserve_pending=false
  plan=focus=focused=nil,pending=nil,lease=window_close_focus_recovery,non_managed=true
```

`confirmedManagedFocusToken` is cleared as a result — later records show
`confirmed=nil` and `nonManaged=true`.

**2. Finder creates the inline rename editor as its own WindowServer window.**
A first attempt (`windowId 19002`) is rejected repeatedly because no AX element
resolves for it:

```
prepare_create_rejected window=19002 context=create reason=missing_ax_ref
  window_info_pid=85938 window_info_level=101 window_info_parent=19001
  ws_float=false ws_doc=false ws_frame=(1512,705 237x485)
```

Six such rejections are recorded with `create_retry_scheduled` attempts 1–5.

**3. The rename editor is then admitted as a managed floating window.** For
`windowId 19004`, AX facts do resolve, and Nehir tracks it:

```
track_prepared_create token=WindowToken(pid: 85938, windowId: 19004)
  workspace=B08E3CE1-B4A2-450A-BB28-F60B7000AB3E monitor=Optional(ID(displayId: 1))
  admissionContext=windowCreate mode=floating bundle=com.apple.finder
  role=AXTextField subrole=nil titleLength=nil title=nil
  frame=(1489,735 50x21) transient=true degraded=false level=0 parent=19001

window_admitted token=WindowToken(pid: 85938, windowId: 19004) mode=floating context=window_create
```

The admitted surface has `role=AXTextField`, `subrole=nil`, and WindowServer
`parent=19001` — it is the rename editor, a child surface of the Finder browser
window, not a user-addressable window. Nehir records floating geometry for it:

```
floating_geometry_updated token=WindowToken(pid: 85938, windowId: 19004)
  frame=(1489.0, 573.0, 50.0, 21.0) restore=true
```

(The `y` difference against `frame=(1489,735 50x21)` is consistent with the same
rectangle expressed top-left versus bottom-left: `1329 − 735 − 21 = 573`. This
record is not by itself evidence that the editor was moved.)

Nehir's own workspace-bar projection independently classifies the same surface as
not user-addressable:

```
token=WindowToken(pid: 85938, windowId: 19004) bundleId=com.apple.finder
  rejected reason=nonStandardAXSurface frame={{1489.0, 573.0}, {50.0, 21.0}}
  transientWindowServerEvidence=true parentWindowId=19001 sticky=false scratchpad=false
```

**4. Admitting the editor drives a layout refresh whose focus validation has no
confirmed managed focus, so it takes the "next window" branch:**

```
reason=ensure_focused_token_valid branch=next_window confirmed=nil confirmedEntryWs=nil
  activeRequest=nil activeRequestWs=nil nonManaged=true
  preferredFocus=WindowToken(pid: 85938, windowId: 19001) confirmedFocus=nil
  columns=12 activeColumnIndex=1 currentViewStart=-6.0 targetViewStart=-6.0
```

**5. Nehir fronts the Finder browser window, taking keyboard focus off the
editor:**

```
pending_focus_started request=4 token=WindowToken(pid: 85938, windowId: 19001)
  workspace=B08E3CE1-B4A2-450A-BB28-F60B7000AB3E reason=focusNextWindow

managed_focus_requested token=WindowToken(pid: 85938, windowId: 19001)
focus_confirmed token=WindowToken(pid: 85938, windowId: 19001) source=focusedWindowChanged
managed_focus_cancelled token=WindowToken(pid: 85938, windowId: 19004)
```

**6. The editor is then destroyed:**

```
destroy_liveness_decision window=19004 origin=cgs_space_destroyed outcome=defer
  reason=window_server_unresolved
destroy_liveness_decision window=19004 origin=cgs_window_closed outcome=remove
  reason=liveness_verification_disabled
window_removed token=WindowToken(pid: 85938, windowId: 19004) phase=destroyed
```

Ordering is the load-bearing detail: the focus request for `19001` is issued
**before** `19004` is destroyed, so the destruction follows the focus change
rather than causing it.

## Candidate cause

Nehir admits Finder's inline rename editor as a managed floating window, and the
focus-recovery pass that runs on the resulting layout refresh fronts the parent
Finder window `19001`. Fronting the parent removes keyboard focus from the rename
editor, which makes Finder dismiss it.

Two independent source-level defects combine.

### (a) A WindowServer-parented child surface is admitted as a managed window

`WindowRuleEngine.decision(...)` reaches
`parentedWindowServerSurfaceDecision(...)`, which returns `.floating` — a
*managed* disposition — for **any** surface with a non-zero WindowServer parent,
with no check on AX role, subrole, or window affordances:

- `Sources/Nehir/Core/Rules/WindowRuleEngine.swift:691-711` — guards only on
  `facts.windowServer?.parentId != 0`, then returns `disposition: .floating`.

`.floating` yields a non-nil tracked mode via
`WMController.trackedModeForLifecycle` (`Sources/Nehir/Core/Controller/WMController.swift:2817-2828`),
so `prepareCreateCandidate` admits the surface
(`Sources/Nehir/Core/Controller/AXEventHandler.swift:5426-5612`).

This admission happens even though the same metadata is judged non-addressable
elsewhere: `WorkspaceManager.barProjectionDecision` rejects it via
`isStandardAXWindowSurface`, which requires `role == kAXWindowRole` and a `nil` or
standard subrole — `Sources/Nehir/Core/Workspace/WorkspaceManager.swift:2761-2762`
and `:2796-2799`. An `AXTextField` fails that test, matching the observed
`rejected reason=nonStandardAXSurface`. So the admission gate and the
addressability gate disagree about the same surface.

Note also that the heuristic path would *not* have been reached for this window:
`AXWindow.heuristicDisposition` (`Sources/Nehir/Core/Ax/AXWindow.swift:755-817`)
also returns `.floating` for a non-standard subrole, so neither path treats
"parented, non-window-role child surface" as unmanaged.

### (b) Focus recovery re-fronts a window while an app-owned transient surface legitimately holds focus

`WMController.ensureFocusedTokenValid` selects its branch from
`activeFocusRequestToken` → `confirmedManagedFocusToken` → otherwise
`resolveAndSetWorkspaceFocusToken` + `focusWindow(..., reason: .focusNextWindow)`
— `Sources/Nehir/Core/Controller/WMController.swift:4111-4209`, with the fronting
call at `:4209`.

Because the context menu cleared managed focus (`confirmed=nil`,
`nonManaged=true`), the first two branches are unavailable and the third runs.
`focusWindow` then calls `performWindowFronting`, which issues `activateApp`,
`focusSpecificWindow`, and `raiseWindow`
(`Sources/Nehir/Core/Controller/WMController.swift:4385-4432` and `:4343-4353`).

The one guard that could stop this is
`shouldSuppressManagedFocusRecovery = isNonManagedFocusActive && hasFrontmostOwnedWindow`
(`Sources/Nehir/Core/Controller/WMController.swift:4339-4341`). It requires a
frontmost **Nehir-owned** window. Here Finder is frontmost, so the guard is
`false` and recovery proceeds. The guard therefore protects Nehir's own overlays
but not a third-party app's own transient focus surface.

The refresh path that requests this validation is
`Sources/Nehir/Core/Controller/LayoutRefreshController.swift:1217-1224`, executed
at `:528-530`.

### Why Return works and the context menu does not — hypothesis

**Labelled `hypothesis`; not established by the inlined evidence.** Return-driven
rename does not open a menu, so `confirmedManagedFocusToken` is expected to remain
`19001`. `ensureFocusedTokenValid` would then take the
`confirmed_in_workspace` branch, which commits a selection **without** calling
`focusWindow`/`performWindowFronting` — no fronting, no focus steal. The capture
does contain a later `branch=confirmed_in_workspace:WindowToken(pid: 85938,
windowId: 19001)` record, showing that branch is reachable for this same window,
but the capture does not include a Return-driven rename, so this explanation is
unverified.

## Falsifier

The candidate cause predicts that in a capture of a failing context-menu rename
there is **both**:

1. a `window_admitted ... mode=floating` record for a `com.apple.finder` surface
   whose `track_prepared_create` shows `role=AXTextField` and `parent=<browser
   window id>`; and
2. a subsequent `pending_focus_started ... reason=focusNextWindow` targeting the
   **parent browser window**, issued *before* that surface's `window_removed`.

The cause is **wrong** if a capture shows the rename failing while either the
editor surface is never admitted, or no `focusNextWindow` request targets the
parent window ahead of the editor's removal. In that case the dismissal has a
different actor and this document should be discarded.

## Pre-implementation proposal and landed deviation

The investigation proposed the invariant: **a WindowServer child surface that
is not a standard AX window is not a managed window, and managed focus recovery
does not front a window while another surface of the same application
legitimately holds focus.**

It considered two changes. PR #193 shipped the first and left the second out of
scope because removing the false managed admission also removes the layout
refresh that triggered the observed focus recovery:

1. **Tighten the parented-surface admission rule.** In
   `WindowRuleEngine.parentedWindowServerSurfaceDecision`
   (`Sources/Nehir/Core/Rules/WindowRuleEngine.swift:691-711`), a parented surface
   should be `.unmanaged` unless it presents as a standard AX window. The
   predicate already exists in effect as
   `WorkspaceManager.isStandardAXWindowSurface`
   (`Sources/Nehir/Core/Workspace/WorkspaceManager.swift:2796-2799`): AX role
   `kAXWindowRole` with a `nil` or `kAXStandardWindowSubrole` subrole. Reusing one
   shared predicate for both admission and bar projection removes the observed
   disagreement, and is what makes this a mechanism fix rather than a
   Finder-shaped patch: it equally covers parented editors, popovers, and helper
   surfaces in other apps.
   - Boundary cases to reason through: parented surfaces that *are* standard
     windows (real child/utility windows must stay managed); parented surfaces
     whose AX fetch failed (`attributeFetchSucceeded == false`, which must not be
     read as "non-standard" and silently unmanage a real window); the existing
     `degradedWindowServerChildEvidence` and Gecko transient-dialog paths, which
     already special-case child surfaces and must not regress.

2. **Do not front a window when the focused surface belongs to the same
   application.** `ensureFocusedTokenValid`'s `next_window` branch
   (`Sources/Nehir/Core/Controller/WMController.swift:4200-4209`) should not call
   `focusWindow` while non-managed focus is active and the frontmost application
   owns the surface holding focus; updating the remembered selection without
   fronting is sufficient there. The existing guard
   `shouldSuppressManagedFocusRecovery`
   (`Sources/Nehir/Core/Controller/WMController.swift:4339-4341`) encodes this
   idea already but only for Nehir-owned windows; the concept to model is
   "another surface legitimately holds focus", of which "Nehir's own window is
   frontmost" is one case.
   - Boundary cases to reason through: genuine window close, where recovery
     *must* front a successor; workspace switch with no confirmed focus; an app
     terminating while non-managed focus is active; and interaction with the
     existing `windowCloseFocusRecovery` lease, which is already active in the
     captured sequence (`focus_lease=window_close_focus_recovery`).

Change 1 alone would stop the editor from being admitted, and is expected to be
sufficient for issue #179. Change 2 is the more general protection: it addresses
the class of "Nehir fronts a window out from under an app's own transient focus
surface", which can arise from any admitted transient. Whether to land both, or
change 1 first, is a scoping decision for the user.

No literal timings or geometry constants are introduced by either change. No
migration or compatibility code is implied — no persisted state changes shape.

## Explicitly out of scope

Renaming the disagreeing predicates, unifying the several transient/child-surface
evidence flags (`transientWindowServerEvidence`,
`degradedWindowServerChildEvidence`,
`userAddressableTransientWindowServerSurface`), and any change to the
`create_retry_scheduled` retry cadence observed for `windowId 19002`. These are
worth separate consideration and should not ride along with this fix.

## Runtime confirmation

Before PR #193 merged, the user repeated the Finder context-menu reproduction
and confirmed that the rename editor stayed editable. The implementation's
source invariant is that no `window_admitted` record can be produced for a
parented `com.apple.finder` surface whose successful AX facts identify
`role=AXTextField`; such a surface is classified as unmanaged instead.
