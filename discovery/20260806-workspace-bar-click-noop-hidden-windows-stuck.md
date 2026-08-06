# Workspace-bar clicks switch interaction + animate layout, but the target workspace's windows never reveal — Discovery

Nehir build `v9ff7c9` (commit `9ff7c9e3` on `main`). Status: **mechanism under
investigation — observations established, candidate cause not yet confirmed in
source.** An earlier draft of this doc pinned the cause on a `com.apple.loginwindow`
guard; that was wrong (see [Ruled out](#ruled-out)) and has been removed.

## Symptom (observed)

Clicking entries on the floating workspace bar appears to do nothing: the
on-screen workspace does not change and no window is raised. Internally the
clicks *are* detected, the interaction workspace advances, and the niri layout
engine records target frames and a viewport-target advance for the clicked
workspace — but the target workspace's windows never actually reveal on screen.

## User-reported symptoms NOT established by this trace

The following were reported by the user but are **not corroborated by any event
in this capture**. They are recorded here as unverified user testimony, not as
facts, and must not be treated as evidence of a mechanism until a capture that
includes the relevant input is obtained.

- **"The screen did not respond to three-finger left/right swipes."** The trace
  contains **no** trackpad-gesture event of any kind: `swipe`, `touch`, `finger`,
  `trackpad`, and `multitouch` all return 0 occurrences. The only `gesture`
  hits are the literal `gesture=false` flag on niri viewport records and the
  cumulative `interactiveGesture` uptime counter (not a per-event log). The
  mouse-focus section records only `tap.mouseMoved` (755 events) — no other tap
  type. So this trace neither confirms that a swipe arrived and was ignored, nor
  confirms that no swipe occurred. The gesture-input path was simply not
  exercising anything captured here.
- **A new trace cannot yet be recorded** because the state is not reproducible on
  demand (no known steps to reach it); see [Reproduction](#reproduction-state-observed-not-yet-a-deterministic-recipe).

Neither item above should be read as evidence for or against the candidate
cause. They are open questions pending a capture that includes gesture input.

## Capture and topology

Single 15.96 s runtime trace capture, `2026-08-06T16:36:09Z → 16:36:25Z`. One
monitor: `ID(displayId: 1)`, `frame=(0.0, 0.0, 2056.0, 1329.0)`,
`hasNotch=true`. Seven configured workspaces; the bar is visible and enabled,
`actualPanelFrame=(673.0, 1258.0, 709.0, 32.0)` (bottom of screen).

Relevant workspaces:

| index | id (prefix) | windows |
| ----- | ----------- | ------- |
| 1     | `70D23777…` | 9 windows (Teams/Slack/VSCode/helium×3/Ghostty/Claude) |
| 4     | `D1BEBF15…` | Ghostty + helium — the **visible** workspace at capture start |

## What the user did (observed)

Five bar clicks across ~13 s, each landing inside the bar frame and producing
an `explicit_workspace_placement_intent` decision event. Pointer location is
quoted at each click's timestamp:

| time (UTC) | pointer loc       | gen | target ws |
| ---------- | ----------------- | --- | --------- |
| 16:36:10   | `(759.8,1275.8)`  | 38  | ws1 `70D23777` |
| 16:36:15   | `(989.4,1269.2)`  | 39  | ws2 `3AA752A7` |
| 16:36:16   | `(1078.3,1265.4)` | 40  | ws3 `71DF9694` |
| 16:36:17   | `(1133.7,1268.4)` | 41  | ws4 `D1BEBF15` |
| 16:36:23   | `(925.8,1272.5)`  | 42  | ws1 `70D23777` |

The mouse moved continuously over the bar throughout (755 `tap.mouseMoved`
events, all `direct=0 canHandle=0 resolved=nil`). This is normal interactive
use, not a lock-screen interaction.

## What advanced (observed)

- **Interaction layer advanced.** `interactionWorkspace` moved `D1BEBF15` (ws4)
  → `70D23777` (ws1) and stayed on ws1 at end of capture.
- **Layout engine ran a ws1 navigation for the window-entry clicks.** The niri
  viewport trace shows `reason=navigate.window source=workspaceBarWindow
  targetWorkspace=1`, ws1 enumerated as 8 columns with selected nodes and
  **on-screen target frames computed** — e.g. window w336
  (`WindowToken(pid:20145,windowId:336)`) recorded `cur=65,7,1926,1251` and
  `target=65,7,1926,1251` (a visible on-screen frame as a *target*).
- **Viewport-target advances are recorded.** The niri viewport trace shows
  `reason=relayout.viewportOffsetChanged`, `reason=spring`, `reason=scroll`
  entries and `animating=true`. Note these are viewport-state *decisions*
  logged by the layout engine; they establish that the engine intended to
  animate the viewport, **not** that the animation reached the AX frame-apply
  layer (see [resolution gap](#what-this-trace-can-and-cannot-establish)).

## What did NOT happen (observed) — the no-op

- **No ws1 window ever revealed.** Every one of ws1's 9 windows is
  `observedVisible=false` at both start and end. Across the entire capture there
  are **0** occurrences of `70D23777` with `phase=tiled` or `observedVisible=true`.
  Their phase/hidden state is identical at start and end:

  ```
  win1089 phase=offscreen hidden=layoutTransient(left)
  win413  phase=hidden    hidden=workspaceInactive
  win233  phase=hidden    hidden=workspaceInactive
  win481  phase=hidden    hidden=workspaceInactive
  win282  phase=offscreen hidden=layoutTransient(left)
  win336  phase=offscreen hidden=layoutTransient(left)
  win756  phase=offscreen hidden=layoutTransient(left)
  win2026 phase=offscreen hidden=layoutTransient(left)
  win2249 phase=offscreen hidden=layoutTransient(left)
  ```

- **No AX frame was ever written to a ws1 window.** The recent-AX-frame-apply
  trace (the `enqueue id=…` / `confirmed id=…` log) contains writes only for
  ws4's windows: `id=303`, `id=331`, `id=597`. Timestamps there are
  `2026-08-06T14:59:04Z` (ws4 settling, before capture) and `2026-08-06T16:36:20Z`
  (one ws4 window, 331). No ws1 window id ever appears.
- **The visible workspace stayed ws4.** The only `phase=tiled,
  observedVisible=true` windows at end are ws4's 331/303/597. `visibleWorkspaces=1`,
  and that one is ws4.
- **Live AX frame stayed offscreen.** In the layout-engine snapshot w336 has its
  computed target frame `65,7,1926,1251` but `live=-1613,44,1614,1045` and
  `replacement=-1613,240,1614,1045` — i.e. its *actual* AX frame is parked
  offscreen-left, and the on-screen target was never written. `observed=nil`,
  `hidden:left`.

Net: the bar click drove interaction + layout-engine selection + viewport
animation, but the window phase transition `hidden→tiled` (and the AX frame
write that places a window on screen) never happened for ws1.

## Candidate cause (hypothesis, source-mapped but not runtime-confirmed)

The niri layout engine and the AX frame-apply layer are two distinct layers
coupled by a per-window `hidden`/visibility state. The engine processed the ws1
clicks — it selected ws1's windows, advanced the viewport target offset to
center each clicked column, computed on-screen target frames, and set
`animating=true`. But ws1's windows were never transitioned out of their `hidden`
state, so the AX frame-apply path skipped them and they stayed parked offscreen.

Source-mapped mechanism (verified in code, not yet confirmed to fire here):

- A window's frame is applied (placed on screen) only if its column intersects
  the working frame at the viewport offset *sampled at plan-build time*
  (`calculateCombinedLayoutUsingPools`, `NiriLayout.swift:248-296`; the geometric
  test `containerIntersectsViewport`, `NiriLayout.swift:397-411`). Columns left
  of the viewport are written into `hiddenHandles` and their windows parked
  offscreen.
- `layoutDiff` (`NiriLayoutHandler.swift:1200-1219`) emits a `.show` only when
  the engine *stops* classifying a previously-hidden window as hidden. If the
  window is still in `hiddenHandles` with the same side as before
  (`previousOffscreenSide == side == .left`), it emits **no** `.show` and **no**
  `.frameChange` — so `LayoutDiffExecutor.execute`
  (`LayoutRefreshController.swift:4393, 4731-4737`) never enqueues an AX frame,
  never clears the hidden state, and never marks the window active.
- `hidden=layoutTransient(left)` in the trace is the persisted `WindowVisibility
  = .hiddenOffscreen(side: .left)` (`WindowModel.swift:57-92`), the exact state
  that keeps a window out of `frameUpdates`.

So the candidate fault is in the hidden→shown transition: the layout engine
recomputed ws1 and set a new viewport target, but the *plan-build-time* viewport
classification still placed ws1's columns off-screen, so no `.show`/frameChange
was produced and the windows were never moved on screen.

## What this trace can and cannot establish

Confirmed by this trace:

- The layout engine ran the ws1 navigation for the window-entry clicks: viewport
  target advanced across ws1's columns (`currentOffset/targetOffset` per click:
  -56.9 → -1989.2 → +400.8 → +909.3 → +1977.1 → +4367.1 → +4875.6, one per ws1
  column), `animating=true` throughout, on-screen target frames computed.
- ws1's windows never revealed (phase/hidden/`observedVisible` identical start
  and end; 0 AX frame applies to any ws1 window).

NOT established by this trace (the resolution gap):

- This capture contains **no** layout-execution diagnostics — there are 0
  `=== relayout route=` lines, 0 `skip-inactive` lines, 0 `blockedReveal`
  lines, 0 `.show`/`.hide` emissions. The runtime-decision trace has only 17
  records (5 intents + 12 completions). So the trace proves the engine *computed*
  ws1's reveal but cannot prove whether `layoutDiff` emitted `.show` for ws1 or
  whether the frame-apply executor received an enqueue. Either branch of the
  hypothesis is consistent with this artifact.

The decisive confirmation requires instrumentation that logs, per ws1 window at
plan-build time, the `hiddenHandles` classification, the emitted `.show`/`.hide`,
and whether an AX frame enqueue was attempted (reproduction-only; not for
shipping).

## Two-bar vs one-bar click distinction (corrected from an earlier draft)

The 5 clicks split across two code paths:

- **3 workspace-pill clicks** (`source=workspace_bar`, gens 39-41):
  `focusWorkspaceFromBar` (`WindowActionHandler.swift:862-894`) — switches the
  workspace and emits one `navigate.workspace` diagnostic, no per-window
  `navigate_window` completions.
- **2 window-entry clicks** (`source=window_navigation_workspaceBarWindow`,
  gens 38, 42): `focusWindowFromBar` → `navigateToWindowInternal`
  (`WindowActionHandler.swift:470-584`) — this is the source of the 12
  `window_action_focus_completion phase=scheduled` events and the viewport-target
  advancements. One window-entry click on a multi-window workspace legitimately
  fans out to several of these as the bar enumerates windows.

Both paths ended the same way (no ws1 window revealed), which is why the user
perceives both as no-ops.

## Ruled out (corrected from an earlier draft)

- **`com.apple.loginwindow` guard is NOT the cause.** An earlier draft argued
  that a full-screen loginwindow window tripped
  `isFrontmostAppLockScreen() || isLockScreenActive`
  (`LayoutRefreshController.swift:991`) while `lockScreenActive=false`. That is
  not supported by the trace: the loginwindow window (`WindowToken(pid:429,
  windowId:2323)`) is the focus-confirmation *stamp* (`stampAtSchedule`) but is
  **not** in the managed-windows list and **not** in the visible-unmanaged
  windows list; it is not a full-screen on-screen window here. `lockScreenActive=false`
  is genuine, the capture is normal interactive use, and the layout engine clearly
  ran the ws1 reveal — which the lockscreen guard would have suppressed entirely.
  That theory is withdrawn.
- **`window_action_focus_completion` "0 fired" is NOT evidence the bar click was
  dropped.** The 12 `phase=scheduled` events all carry `context=navigate_window`,
  which is emitted only by `navigateToWindowInternal`
  (`WindowActionHandler.swift:549`) — a *per-window* navigation path, not the
  workspace-pill click path. The pill-click path (`focusWorkspaceFromBar`,
  `WindowActionHandler.swift:862-894`) does not emit these. So the 12 events are
  a fan-out enumeration of ws1's windows from the window-entry clicks, not the
  bar-transition closures, and their firing (or not) says nothing about whether
  the workspace transition's reveal ran.
- **The Teams `notificationcenter` dialog** (`windowId:233`, `subrole=AXDialog`,
  `windowLevel=20`) rejected as `nonStandardAXSurface` for bar projection is not
  the cause — bar-projection rejection does not affect window reveal/focus.
- The `prepare_create_rejected reason=unstable_window_server_info` retry loop
  for two zero-size windows during the capture is a concurrent disturbance, not
  the cause of the no-op.

## Reproduction (state observed, not yet a deterministic recipe)

The reliably-observed precondition is: the target workspace (ws1) has windows
that are `phase=offscreen hidden=layoutTransient(left)` while another workspace
(ws4) is the visible one, and clicking the bar to switch to ws1 leaves the ws1
windows in that `layoutTransient` state. To reproduce: reach a session where one
workspace's windows are stuck in `layoutTransient` phase (the trigger for that
stuck state is itself part of what is under investigation), then click a
different workspace's bar entry and back. The on-screen workspace does not
change while `interactionWorkspace` does.

Confirmation the state is reached (reproduction-only instrumentation, not for
shipping): log, per window, the phase/hidden value and whether an AX frame
enqueue was issued, at the moment a workspace transition's reveal step runs. A
repro shows ws1 windows staying `hidden` with no enqueue.

## Next step / proposed direction (not an implementation)

The candidate fault is in the workspace-reveal coupling between the viewport
offset and the plan-build-time hidden classification: switching to ws1 sets a
new viewport target and computes target frames, but if the offset sampled at
plan-build time still leaves ws1's columns off-screen, `layoutDiff` emits no
`.show`, the hidden state is never cleared, and no AX frame is applied — so the
screen never changes even though the engine thinks it revealed the workspace.

Invariant a fix must hold: **a workspace switch that sets `visibleWorkspaceId`
must also guarantee that the newly-active workspace's windows transition out of
`hidden` and receive their on-screen frames.** The reveal must not silently
no-op when the stored viewport offset happens to leave the target column
off-screen at plan-build time.

No `Sources/` changes, no test changes, and no git mutations have been made.
Before any fix, the hypothesis should be confirmed at runtime with temporary
reproduction-only instrumentation: log, per window at plan-build time, the
`hiddenHandles` classification, the `.show`/`.hide` emitted by `layoutDiff`
(`NiriLayoutHandler.swift:1200-1219`), and whether `LayoutDiffExecutor.execute`
enqueued an AX frame — during a bar click to a workspace whose windows are stuck
`layoutTransient(left)`. Only then should a fix be planned against the actual
failing step.
