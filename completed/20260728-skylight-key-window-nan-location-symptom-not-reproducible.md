# SkyLight key-window NaN location: pre-fix bytes confirmed, symptom not reproducible

**Completed 2026-07-28.** The *code-shape* half of the
[`20260728-upstream-post-roadmap-candidates.md`](../discovery/20260728-upstream-post-roadmap-candidates.md)
finding for `a4b8611a` / <https://github.com/BarutSRB/OmniWM/issues/505> was
correct: Nehir carried the byte-for-byte pre-fix key-window event record on its
only key-window path. The *user-impact* half is **not supported**. The symptom
described upstream — Chromium web-app (PWA) windows closing when the window
manager is enabled or when focus is moved between windows — **could not be
reproduced**, on Nehir `main` without the port *or* on upstream OmniWM v0.5.7
itself, on the same macOS build as the upstream reporter.

The port shipped as **hardening only**, with no release note, in
<https://github.com/apphane-dev/nehir/pull/187>:

- `0175a6d5` — finite `CGPoint(x: -1, y: -1)`, padded `0x100`-byte buffer with
  declared length `0xF8`, and named event-record offsets in
  `Sources/Nehir/Core/PrivateAPIs.swift`;
- `6bdd9b10` — byte-layout regression coverage in
  `Tests/NehirTests/SkyLightKeyWindowEventRecordTests.swift`, plus the test's
  upstream provenance entry.

The full gate passed after rebasing onto the merge-time `main`: **1491 tests in
130 suites**; `mise run license:check` also passed. The code and release note do
not claim that an observable Chromium defect was fixed.

---

## What the pre-fix record was

Before the port, `makeKeyWindow` built a `0xF8`-byte buffer and filled bytes
`0x20..<0x30` — the window-location field — with `0xFF` in every byte:

```
var eventBytes = [UInt8](repeating: 0, count: 0xF8)
…
for i in 0x20 ..< 0x30 {
    eventBytes[i] = 0xFF
}
```

Those 16 bytes are read back as a `CGPoint`, i.e. two native-endian 64-bit
`Double`s. All-`0xFF` decodes as **NaN** in both coordinates. So every synthesised
key-window event Nehir posted claimed the originating click happened at an
undefined location.

That is indefensible on its own terms regardless of who notices: a synthesised
mouse-derived event should carry a valid position.

## The path is real, and it is the only one

`makeKeyWindow` is the sole mechanism by which Nehir makes a specific window key
— there is no AX-attribute alternative anywhere in the tree. It is reached as:

- `Sources/Nehir/Core/PrivateAPIs.swift:81-93` — `makeKeyWindow` posts the record and `focusWindow` invokes it.
- `Sources/Nehir/Core/Controller/WMController.swift:42-44` — wired as
  `WindowFocusOperations.live.focusSpecificWindow`.
- `Sources/Nehir/Core/Controller/WMController.swift:4141-4150` —
  `performWindowFronting` calls it between `activateApp` and `raiseWindow`.
- `Sources/Nehir/Core/Controller/WMController.swift:4216-4222` — the main
  `focusWindow(_:reason:)` flow supplies `performWindowFronting` as
  `focusBridge.focusWindow`'s `performFocus` closure.
- `Sources/Nehir/Core/Controller/WindowActionHandler.swift:364-383` —
  `front(surface:)` for both `.managed` and `.external` surfaces.
- `Sources/Nehir/UI/CommandPalette/CommandPaletteController.swift:1041` — the
  command palette calls `makeKeyWindow` directly.

So the NaN record was genuinely being posted on ordinary focus changes, not on
some dormant fallback. Nothing about the *reachability* claim was wrong.

## Runtime evidence — the symptom does not occur

Environment for every observation below: macOS **26.5.2 (25F84)** — byte-identical
to the build named in the upstream report — and Google Chrome
**150.0.7871.187**. Three Chromium web-app windows were open throughout, across
two different Chromium browsers:

| bundle id | browser |
| --- | --- |
| `com.google.Chrome.app.aldkillipapfonlifpkkkbfgbhijnbli` | Chrome |
| `net.imput.helium.app.gjcmcplpgihbecacndmmbaenpfgimlec` | Helium |
| `net.imput.helium.app.fmpjfhdchblgclpadggiopjgllgceada` | Helium |

### Observation 1 — focus switching (Nehir `main`, port not applied)

A 31-second capture with the Chrome PWA as `WindowToken(pid: 65530, windowId:
12230)`. Focus was driven by hotkey, not by clicking:

```
reason=focus_direction_dispatch direction=right
      currentToken=WindowToken(pid: 56515, windowId: 10582) targetResolved=true
event=managed_focus_requested  token=WindowToken(pid: 65530, windowId: 12230)
event=managed_focus_confirmed  token=WindowToken(pid: 65530, windowId: 12230)
```

Focus then moved away to `WindowToken(pid: 21468, windowId: 1598)` and back to
the PWA again, repeatedly — the upstream reporter's "scroll through windows"
scenario. There were **no window-destroy events for pid 65530**, and the
end-of-capture state has the window alive and on screen:

```
WindowToken(pid: 65530, windowId: 12230) mode=tiling phase=tiled hidden=nil
    observedVisible=true bundleId=com.google.Chrome.app.aldkillipapfonlifpkkkbfgbhijnbli
    role=AXWindow subrole=AXStandardWindow
```

### Observation 2 — window-manager startup (Nehir `main`, port not applied)

A 21-second capture that includes the WM start itself — the runtime state at the
beginning of the capture reads `startedServices=false`, and every window enters
through the startup rescan. All three PWAs were admitted:

```
event=window_admitted token=WindowToken(pid: 49243, windowId: 12061) context=startup_full_rescan
event=window_admitted token=WindowToken(pid: 50915, windowId: 12092) context=startup_full_rescan
event=window_admitted token=WindowToken(pid: 80358, windowId: 12318) context=startup_full_rescan
```

(pid 49243 and 50915 are the two Helium web apps; pid 80358 is the Chrome web
app.) All three were focused at some point during the capture via
`managed_focus_requested` → `managed_focus_confirmed`, and all three are alive in
the end-of-capture state — two `phase=offscreen` (scrolled out of the Niri
viewport, not closed) and one `phase=tiled observedVisible=true`.

This is the upstream report's headline scenario — *"Chrome WebApps are closed when
enabling OmniWM"* — and it did not occur.

### Observation 3 — a structural difference in startup fronting

In that startup capture, exactly **one** window was fronted on the startup
second: `WindowToken(pid: 49243, windowId: 12061)`, one of the Helium web apps.
The other two PWAs received only `hidden_state_changed` (layout hiding), never a
focus request.

The upstream symptom is mass — *"all chrome apps are closed"*, *"any time I
scroll through windows, **all** web apps close"* — which implies a manager that
touches every window. Nehir's startup, as observed here, fronts a single window.
Nehir's startup sequence has been substantially rewritten relative to upstream's.

This was initially the leading explanation for the non-reproduction. **It is not
sufficient** — see the next observation.

### Observation 4 — upstream OmniWM v0.5.7 does not reproduce it either

The exact upstream release named in the report (v0.5.7, and the reporter adds
that v0.5.6 behaves the same) was run on this machine, with the same three
Chromium web apps and the same macOS build. The symptom did not occur: the web
apps survive every restart, focus normally under hotkeys, and move between
workspaces.

This eliminates "Nehir's callers diverged from upstream's" as the explanation.
The trigger is not on the window-manager side at all.

## Status of the upstream diagnosis

<https://github.com/BarutSRB/OmniWM/issues/505> carries **no diagnosis and no
confirmation**. Its full timeline is:

```
labeled     2026-07-22  (reporter)
closed      2026-07-24  (maintainer)  a4b8611a
referenced  2026-07-25                a4b8611a
```

Zero comments. The reporter never confirmed the fix worked; the maintainer never
stated the symptom was reproduced. The commit message describes the change as
*adapted* from AltTab v11.3.1 by analogy — the reporter had independently noted
seeing similar behaviour in AltTab v11.30, fixed in v11.3.1.

So the causal chain "NaN window location → Chromium mishandles it → the window
closes" is a **plausible hypothesis that nobody has demonstrated**, upstream or
here. It should not be restated as mechanism in Nehir documentation, commit
messages, or release notes.

The one variable left unexcluded is the Chromium build: the reporter's Chrome
version is not recorded in the issue, and Chromium auto-updates. If the trigger
was a Chromium-side defect since repaired, the symptom is unreproducible by
anyone current, permanently.

## What remained unverified at merge

The **fixed** build was not exercised at runtime before merge. Every observation
above was made without the port applied. The change compiled, the byte-layout
test was falsified against the pre-fix `0xF8`/NaN form, and the full suite passed;
its runtime behaviour with real PWA windows remained unobserved.

Because the symptom cannot be produced, the hardening cannot be validated by its
intended effect. The remaining negative check is to run a build carrying it with
the same three web apps and confirm nothing regresses. This is post-merge runtime
validation, not a claim that the upstream symptom ever existed in Nehir.

Review of this path also exposed a separate, confirmed observability gap: all
four fallible steps in the private focus sequence lose their `OSStatus`, so a
runtime capture cannot say whether process lookup, front-process selection,
mouse-down posting or mouse-up posting failed. That follow-up is intentionally
separate from this hardening port; see
[`20260728-private-api-focus-statuses-are-silently-discarded.md`](../discovery/20260728-private-api-focus-statuses-are-silently-discarded.md).

## Consequence for the sweep record

In [`20260728-upstream-post-roadmap-candidates.md`](../discovery/20260728-upstream-post-roadmap-candidates.md),
`a4b8611a` was ranked tier-1 and described as *"highest confidence in the
sweep"*. That ranking was derived entirely from static reading of the pre-fix
bytes; no runtime check stood behind it. The code-shape half survives; the
priority and the implied user impact do not.

Generalisable lesson for future sweeps: **"Nehir carries the pre-fix bytes" is a
statement about code, not about behaviour.** An upstream fix for an unconfirmed,
undiagnosed report inherits that report's uncertainty no matter how cleanly the
pre-fix shape matches locally. Rank such items below anything with an observed
symptom, and say in the sweep entry that the upstream evidence is a single
unconfirmed report.
