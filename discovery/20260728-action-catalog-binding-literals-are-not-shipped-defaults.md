# Discovery: `ActionCatalog` binding literals are not the shipped defaults

Status: confirmed and actionable — the shipped modifier families are intentional,
but 44 assigned catalog entries declare a shorthand literal that silently gains
`Command` before it becomes an `ActionSpec.defaultBinding`. Runtime/UI surfaces
mostly consume the transformed value correctly; source comments and durable
planning records have repeatedly mistaken the shorthand for the real default.

Verified against Nehir `main` at `45a5b965` and BarutSRB/OmniWM `main` at
`044441c4` on 2026-07-28. This document changes no source files.

Follow-up intent: revisit this hidden shorthand rather than treating the current
representation as settled. Preserve the shipped default map unless a separate,
explicit backwards-compatibility decision authorizes changing it.

## Executive conclusion

The current behavior is not an accidental extra modifier:

- Nehir commit `4b0ed1c5` deliberately replaced the inherited semantic-modifier
  model with physical chords, changed `defaultBinding(for:)` to add `cmdKey`,
  documented `Option+Command` / `Option+Shift+Command` /
  `Control+Option+Command` as the public default families, and added tests for
  the baked physical results.
- The *shape* of the implementation is inherited legacy. Upstream commit
  `254820f9` had introduced `defaultBinding(for:)` so Option-looking literals
  meant semantic Hyper rather than physical Option. Nehir imported that helper
  in `9a468779`, then repurposed it to mean “Option plus an implicit Command”
  instead of rewriting every literal.
- Upstream later removed the semantic transform in `1aadf760`: `action(...)`
  began storing `defaultBinding: binding` directly. Upstream's current physical
  defaults differ from Nehir's, so its binding choices must not be copied, but
  the history confirms what the helper originally was: a shorthand-expansion
  layer, not an inherent requirement of `ActionCatalog`.

Therefore the product policy is intentional, while the call-site representation
is misleading. The strongest behavior-preserving fix shape is to make every
assigned literal equal its shipped chord and remove the hidden transform. A
product decision to remove Command from any defaults is a separate backwards-
compatibility change and must not be smuggled into that readability refactor.

## Current source mechanism

Every catalog entry goes through `action(...)` in
`Sources/Nehir/Core/Input/ActionCatalog.swift:846-867`. The helper stores:

```swift
defaultBinding: defaultBinding(for: binding)
```

`defaultBinding(for:)` at `ActionCatalog.swift:869-883` applies this rule:

1. pass `.unassigned` through;
2. pass the exact physical Hyper mask through;
3. pass bindings that already contain `Command` through;
4. pass bindings without `Option` through;
5. otherwise return the same key code with `cmdKey` added.

The Hyper special case is behaviorally redundant today because physical Hyper
already contains `Command`, but it documents an intended exception inherited
from the modifier-model transition. `KeySymbolMapper.realHyperModifiers` is the
physical `Control+Option+Shift+Command` mask
(`Sources/Nehir/Core/Input/KeySymbolMapper.swift:131`).

The transformed `ActionSpec.defaultBinding` is the effective authority:

- `ActionCatalog.defaultHotkeyBindings()` materializes it at
  `ActionCatalog.swift:97-105`;
- `DefaultHotkeyBindings.all()` forwards that result at
  `Sources/Nehir/Core/Input/DefaultHotkeyBindings.swift:10-12`;
- `HotkeyBindingRegistry.defaults()` forwards it at
  `Sources/Nehir/Core/Input/HotkeyBinding.swift:232-239`.

So a reader who stops at a `buildSpecs()` literal is reading an intermediate
notation, not a user-visible default.

## Complete effective-default inventory

Line references in this section are to
`Sources/Nehir/Core/Input/ActionCatalog.swift` at Nehir `45a5b965`. Numbered
families are grouped, but every assigned spec is covered.

### Transformed entries: literal differs from shipped default

These are the 44 concrete assigned bindings to which `Command` is added.

| Action id(s) | Catalog line(s) | Literal at call site | Effective shipped default |
| --- | ---: | --- | --- |
| `moveToWorkspace.0...8` | 159 | `Option+Shift+{1-9}` | `Option+Shift+Command+{1-9}` |
| `workspaceBackAndForth` | 169 | `Control+Option+Tab` | `Control+Option+Command+Tab` |
| `focus.left/down/up/right` | 194, 200, 206, 212 | `Option+Arrow` | `Option+Command+Arrow` |
| `focusPrevious` | 221 | `Option+Tab` | `Option+Command+Tab` |
| `move.left/down/up/right` | 382, 388, 394, 400 | `Option+Shift+Arrow` | `Option+Shift+Command+Arrow` |
| `toggleFullscreen` | 481 | `Option+Return` | `Option+Command+Return` |
| `moveColumnToFirst`, `moveColumnToLast` | 511, 517 | `Control+Option+Home/End` | `Control+Option+Command+Home/End` |
| `focusColumnFirst`, `focusColumnLast` | 529, 535 | `Option+Home/End` | `Option+Command+Home/End` |
| `focusColumn.0...8` | 545 | `Control+Option+{1-9}` | `Control+Option+Command+{1-9}` |
| `cycleColumnWidthForward`, `cycleColumnWidthBackward` | 577, 583 | `Option+Period/Comma` | `Option+Command+Period/Comma` |
| `toggleColumnFullWidth` | 613 | `Option+Shift+F` | `Option+Shift+Command+F` |
| `expandColumnToAvailableWidth` | 619 | `Control+Option+F` | `Control+Option+Command+F` |
| `resetWindowHeight` | 625 | `Control+Option+R` | `Control+Option+Command+R` |
| `setColumnWidth.decrease10Percent`, `.increase10Percent` | 631, 638 | `Option+Minus/Equal` | `Option+Command+Minus/Equal` |
| `setWindowHeight.decrease10Percent`, `.increase10Percent` | 659, 666 | `Option+Shift+Minus/Equal` | `Option+Shift+Command+Minus/Equal` |
| `balanceSizes` | 673 | `Option+Shift+B` | `Option+Shift+Command+B` |
| `raiseAllFloatingWindows` | 689 | `Option+Shift+R` | `Option+Shift+Command+R` |

### Assigned pass-through entries: literal already is the shipped default

| Reason | Action id(s) and effective default |
| --- | --- |
| Already contains `Command` | `switchWorkspace.0...8` = `Option+Command+{1-9}` (`:151`); `switchWorkspace.next/previous` = `Control+Option+Command+Right/Left` (`:179,185`); `scrollViewport.left/right` = `Option+Command+[/]` (`:282,289`); `toggleNativeFullscreen` = `Option+Shift+Command+Return` (`:487`); `toggleColumnTabbed` = `Option+Shift+Command+T` (`:523`); `openCommandPalette` = `Option+Command+Space` (`:682`); `openMenuAnywhere` = `Option+Command+M` (`:731`); `debug.toggleTraceCapture` = `Control+Option+Command+T` (`:776`); `toggleOverview` = `Option+Command+O` (`:791`). |
| Contains no `Option` | `focusMonitorNext` = `Control+Command+Tab` (`:460`); `focusMonitorLast` = `Control+Command+Grave` (`:472`). |
| Exact physical Hyper | `moveWindowToWorkspaceUp/Down` = `Hyper+Up/Down` (`:306,312`); `moveColumn.left/right` = `Hyper+Left/Right` (`:493,502`). |

### Unassigned pass-through entries

The remaining specs are intentionally unassigned and therefore cannot have a
modifier discrepancy:

- focus variants `focusDownOrLeft`, `focusUpOrRight`, `focusWindowTop/Bottom`,
  `focusWindowDownOrTop`, `focusWindowUpOrBottom`, and
  `focusWindowOrWorkspaceDown/Up` (`:226-275`);
- `toggleViewportScrollLock` (`:296`);
- `moveColumnToWorkspaceUp/Down` (`:321,327`),
  `moveColumnToWorkspace.0...8` (`:331-340`),
  `swapWorkspaceWithMonitor.*` (`:342-351`),
  `focusWorkspaceAnywhere.0...8` (`:353-362`), and
  `moveWindowToWorkspaceOnMonitor.*.*` (`:364-375`);
- the alternate move/consume/expel actions at `:404-453`;
- `focusMonitorPrevious` (`:466`);
- `focusWindowInColumn.1...9` (`:550-559`) and
  `moveColumnToIndex.1...9` (`:561-570`);
- `cycleWindowWidthForward/Backward` and
  `cycleWindowHeightForward/Backward` (`:589-607`);
- `setWindowWidth.decrease10Percent/increase10Percent` (`:645,652`);
- `rescueOffscreenWindows` (`:696`), floating/sticky/scratchpad actions
  (`:703-724`), `openSettings` (`:738`), and
  `createAppRuleForFocusedWindow` (`:745`);
- debug dump/reset/restart actions (`:752-768`),
  `toggleWorkspaceBarVisibility` (`:784`), and the settings toggles at
  `:796-841`.

## Historical intent: intentional policy implemented through inherited shorthand

### 1. Upstream introduced the helper for semantic Hyper

BarutSRB/OmniWM commit
[`254820f9`](https://github.com/BarutSRB/OmniWM/commit/254820f98fde505498763777285c4a43c6649a85)
("Add configurable Hyper and leader-key hotkey sequences", 2026-05-26) added
`defaultBinding(for:)` to `Sources/OmniWM/Core/Input/ActionCatalog.swift`.
It converted assigned Option-bearing literals into `usesHyper: true` bindings:
it removed the physical Option bit and represented the result as semantic Hyper.
The commit message explicitly describes semantic Hyper and a configurable Hyper
trigger.

Nehir's root import `9a468779` (2026-05-30) copied the same mechanism as
`usesModifier: true`. At the fork point, the call-site literal was already a
shorthand by design.

### 2. Nehir deliberately changed what the shorthand means

Later on 2026-05-30, Nehir commit `4b0ed1c5` ("Refactor hotkey terminology and
update tests for physical keybindings") removed the semantic modifier model and
changed the helper from:

```text
Option-bearing literal -> remove Option, set semantic modifier flag
```

to:

```text
Option-bearing literal without Command -> add physical Command
```

The same commit makes the product intent explicit in multiple independent ways:

- `README.md` gained the "Default Shortcut Model" with
  `Option+Command` for navigation/focus/UI,
  `Option+Shift+Command` for moving the focused window,
  `Control+Option+Command` for larger-scope navigation, and physical Hyper for
  structural moves.
- `docs/CONFIGURATION.md` explains why Option alone, Control alone, and
  Control+Option were rejected as public bases, and calls
  `Option+Command` the least-bad built-in base.
- `Tests/NehirTests/ActionCatalogTests.swift` changed from semantic-Hyper
  expectations to baked physical modifier expectations.
- `Tests/NehirTests/SettingsStoreTests.swift` added serialized physical-default
  assertions.

That evidence rules out “the extra Command is an accidental migration shim”.
The current modifier families are deliberate Nehir policy. What remained from
upstream was the hidden shorthand layer and its generic name.

### 3. Upstream later removed the shorthand when its model became literal

BarutSRB/OmniWM commit
[`1aadf760`](https://github.com/BarutSRB/OmniWM/commit/1aadf76099683bd4bf92d06f3455a4166c64aeb0)
("Redesign Hyper as a literal chord with an optional System Hyper Trigger",
2026-06-18) removed `defaultBinding(for:)` and changed `action(...)` to store
`defaultBinding: binding` directly.

Upstream simultaneously chose different physical defaults, including physical
Option-only chords, so that commit is not a default map for Nehir. It is useful
as architectural provenance: once upstream no longer needed semantic shorthand,
it made the catalog literals truthful and deleted the transform.

## Surface audit

### Rendered and persisted surfaces are consistent

The important user-visible surfaces derive from effective catalog bindings
rather than re-reading literals:

- Settings Hotkeys builds its defaults map from
  `HotkeyBindingRegistry.defaults()`
  (`Sources/Nehir/UI/HotkeySettingsView.swift:463`).
- Command-palette rows render the live trigger's `displayString`
  (`Sources/Nehir/UI/CommandPalette/CommandPaletteController.swift:609`).
- Onboarding shortcut rows use `ActionCatalog.defaultHotkeyBindings()`
  (`Sources/Nehir/UI/Onboarding/OnboardingStepControls.swift:258-264`).
- `InteractiveMoveDemo`'s palette overlay also resolves display strings through
  `ActionCatalog.defaultHotkeyBindings()`
  (`Sources/Nehir/UI/Onboarding/InteractiveMoveDemo.swift:731-737`).
- TOML persistence/export and diagnostics flow through registry defaults in
  `SettingsStore.swift:645,666`, `SettingsDiagnosticsIssue.swift:236-243`,
  `CanonicalTOMLConfig.swift:429`, `SettingsExport.swift:157`, and
  `SettingsFilePersistence.swift:448`.
- The Raycast extension under `raycast/nehir/` invokes `nehirctl` commands and
  declares no independent hotkey defaults.

No rendered Settings, command-palette, onboarding-label, TOML, diagnostics, or
Raycast discrepancy was found.

### Current shipped documentation is consistent

- `README.md:162-165` describes the real modifier families.
- `docs/CONFIGURATION.md:57-201`, including its current-default matrix, matches
  the effective catalog values.
- `docs/glossary.md:244` and `docs/viewport-navigation-spec.md:192` correctly
  describe `Command+Option+[` and `Command+Option+]`.
- `README.md:95` and `docs/IPC-CLI.md:424` correctly describe trace capture as
  `Control+Option+Command+T`.
- `HotkeysTOMLCodec.swift:13-18` and Hotkey Settings help text also use the
  effective physical chords.

So the shipped docs are not the defect. The defect is that nearby source and
planning records can still be generated by reading the literals as final.

### Current source/test comments that are wrong

Confirmed stale static claims in `main`:

1. `Sources/Nehir/Core/Controller/NiriLayoutHandler.swift:1582` calls
   "Focus Previous Window" `Option-Tab`; the default is
   `Option+Command+Tab`.
2. `Tests/NehirTests/FocusPreviousCrossWorkspaceTests.swift:11,20,55,112`
   repeats `Option-Tab` while testing that command's behavior.
3. `Sources/Nehir/UI/WorkspaceBar/WorkspaceBarManager.swift:656,759` calls
   Shift-click the mouse analogue of `Opt+Shift+N`; the default move-to-workspace
   chord is `Option+Shift+Command+N`.
4. `Sources/Nehir/UI/Onboarding/InteractiveMoveDemo.swift:777` says focus is
   `Option+Arrow` and move is `Option+Shift+Arrow`; the displayed defaults are
   `Option+Command+Arrow` and `Option+Shift+Command+Arrow`.

The onboarding demo has a behavioral mismatch as well as a comment mismatch.
Its local key monitor at `InteractiveMoveDemo.swift:777-796` checks only
`mods.contains(.option)` (plus optional Shift). Therefore the real shipped
chords work, but bare Option chords that do *not* work as Nehir defaults also
operate the sandbox. The dynamically rendered labels are correct, while the
accepted-key set is a permissive superset that can teach the wrong chord.

### Durable planning records that read literals as defaults

The plans branch contains more instances than the two originally observed.
These are not shipped product docs, but they are durable implementation evidence
and have already propagated incorrect applicability or reasoning:

- `completed/20260616-omniwm-240-focus-previous-cross-workspace.md:47-49,140-143,197-211`
  repeatedly calls the default `Option-Tab`.
- `completed/20260621-workspace-number-modifier-click-move-window.md:3,13-26,193,327-332`
  and `discovery/20260621-workspace-number-modifier-click-move-window.md:37-40,83-86,238-267,406,463,488`
  call move-to-workspace `Opt+Shift+N` and even describe the family as
  `Opt+Shift = move`; the real family is `Option+Shift+Command`.
- `discovery/20260705-move-focused-window-to-workspace-noop-under-nonmanaged-focus.md:11`
  labels the same command `Opt+Shift+N`.
- `completed/20260614-onboarding.md:195,267` describes onboarding focus/move as
  `Opt+Arrow` / `Opt+Shift+Arrow`, matching the demo's stale local matcher rather
  than the shipped defaults.
- `completed/20260610-settings-and-onboarding-redesign.md:753` describes moving
  a window with `Shift+Option+1`; the shipped chord also contains Command.
- `discovery/20260617-nehir-69-fullscreen-restore-on-focus.md:35-41,63-95,176-177`
  identifies `Option+Return`, `Option+Shift+F`, and `Control+Option+F` as defaults.
  The effective defaults are respectively `Option+Command+Return`,
  `Option+Shift+Command+F`, and `Control+Option+Command+F`. Its statement that
  the reporter “swapped” the `Option+Shift+F` default therefore needs
  re-evaluation; the reporter's explicit rebind remains evidence, but it did not
  equal the catalog's effective column-full-width default.
- `discovery/20260621-niri-fullscreen-expectations-and-fix.md:129-162,385-391`
  and `planned/20260621-niri-fullscreen-expectations-and-fix.md:129,230,319-323`
  repeat the `Option+Return` and `Option+Shift+F` default claims.
- `discovery/20260712-omniwm-cleanup-sweep-20260505-regroom.md:118-131`
  concludes that BarutSRB/OmniWM#192 is live in Nehir because Nehir allegedly
  ships Option-only Arrow and Option+Shift Arrow defaults. It does not: Nehir
  ships Command-bearing families. The upstream report's exact text-editing
  collisions therefore do not establish current applicability, and that verdict
  must be revisited rather than used as evidence for a defaults redesign.

This inventory distinguishes inaccurate *default* labels from quoted user
rebinds: an explicit `Option+Shift+F` in a reported `hotkeys.toml` can be
accurate evidence even where an adjacent parenthetical claim about the built-in
default is not.

## Test coverage: transformed results are partly pinned, literals are not

Existing tests exercise effective values, not the shorthand itself:

- `Tests/NehirTests/ActionCatalogTests.swift:20-39`, named
  `workspaceSwitchDefaultsUseBakedPhysicalModifier`, pins
  `switchWorkspace.1 = Option+Command+2` and
  `moveToWorkspace.1 = Option+Shift+Command+2`.
- `Tests/NehirTests/SettingsStoreTests.swift:658-677` serializes registry
  defaults and checks selected transformed/pass-through values including
  workspace navigation, physical Hyper actions, native fullscreen, command
  palette, menu anywhere, and overview.
- `Tests/NehirTests/HotkeySettingsViewTests.swift:29` pins the numbered display
  pattern `Option+Command+{N}`.
- `Tests/NehirTests/CreateAppRuleForFocusedWindowTests.swift:30,49` pins that
  action's unassigned result through both spec and registry paths.
- `ActionCatalogTests.swift:12-18,128-164` mostly pins catalog/registry structure,
  surface visibility, config keys, and IPC coverage, not default values.

No test directly names `defaultBinding(for:)`, asserts the complete 44-entry
transformation set, or fails merely because a call-site literal is misleading.
The strongest existing serialization test checks a representative subset, not
the full default map. This is why comments and planning documents could be
wrong while the runtime tests remained green.

## Root cause chain

1. A reader sees a concrete `KeyBinding` literal beside an action id and treats
   it as the default.
2. The literal is actually an undocumented intermediate notation; `action(...)`
   rewrites it several hundred lines later.
3. The helper name `defaultBinding(for:)` sounds like lookup/normalization, not
   “conditionally add a user-visible modifier”, and has no explanatory comment.
4. The indirection survived from upstream's semantic-Hyper implementation,
   where shorthand expansion was a first-class feature.
5. Nehir deliberately changed the public model to physical chords but
   repurposed the helper instead of making the physical literals authoritative.

The fundamental defect is therefore not the modifier policy. It is a stale
semantic-shorthand architecture hidden behind literal-looking values and a
generic helper name.

## Fix-shape conclusion

### Preferred if current defaults are to be preserved: truthful literals

Use candidate (a) as a behavior-preserving representation change:

1. Add `cmdKey` explicitly to all 44 transformed literals.
2. Change `action(...)` to store `defaultBinding: binding` directly.
3. Delete `defaultBinding(for:)`.
4. Correct the stale source/test comments and durable planning records listed
   above.
5. Make `InteractiveMoveDemo` validate the actual default triggers (or derive
   its event matching from the same catalog entries) instead of accepting every
   Option-bearing Arrow chord.
6. Add a complete effective-default fixture/snapshot — preferably the full
   serialized default `hotkeys.toml` keyed by action id — and require it to be
   byte-for-byte/equivalent before and after this refactor.

This has the lowest future cognitive cost: a literal becomes a literal, source
searches become trustworthy, and no extra annotation vocabulary is needed.
Upstream's `1aadf760` is precedent for deleting the helper once bindings are
physical, although Nehir must retain its own Command-bearing values.

### Alternatives

- Candidate (b), retaining the transform, is only acceptable if the shorthand is
  made unmistakable: rename the parameter/helper to describe the mutation (for
  example a base-layer shorthand that explicitly adds Command), document the
  modifier-family policy at the helper, and avoid raw `KeyBinding` syntax that
  looks final. Merely adding a doc comment to `defaultBinding(for:)` does not fix
  the misleading call sites.
- Candidate (c), adding a per-entry marker, makes the distinction explicit but
  preserves two representations of one physical chord and adds review burden to
  every new action. It is harder to justify than direct truthful literals unless
  the project wants semantic family constructors for a broader configurable
  shortcut system.

## Backwards-compatibility boundary — decision must remain explicit

Two materially different changes must not be conflated:

1. **Representation-only preservation:** expand each shorthand to its current
   effective physical chord, then remove the helper. If the complete
   id-to-trigger map and serialized defaults are identical before and after,
   runtime behavior and config fallback behavior are unchanged.
2. **Product default change:** remove or alter Command on any action. That affects
   fresh installs and every missing or unparsable hotkey entry because
   `HotkeysTOMLCodec.decodeDocument` maps over the supplied defaults and returns
   the default whenever an override is absent or invalid
   (`Sources/Nehir/Core/Config/HotkeysTOMLCodec.swift:216-225`). Explicit valid
   user overrides remain explicit, so it is not accurate to say every existing
   user necessarily changes; users relying on omitted/defaulted entries do.

Choosing to preserve, break, or migrate product defaults is a user-owned
backwards-compatibility decision. A future implementation plan must state which
of those is authorized. This discovery recommends only that, if preservation is
chosen, it be proven by complete default-map equivalence rather than inferred
from a partial test subset.

## Planning inputs

A follow-up plan should own only catalog/default readability and the directly
stale surfaces:

- `Sources/Nehir/Core/Input/ActionCatalog.swift`
- `Sources/Nehir/UI/Onboarding/InteractiveMoveDemo.swift`
- `Sources/Nehir/UI/WorkspaceBar/WorkspaceBarManager.swift`
- `Sources/Nehir/Core/Controller/NiriLayoutHandler.swift`
- binding/default tests under `Tests/NehirTests/`
- the specific plans-branch records listed above

It should explicitly avoid changing command behavior, action ids, TOML keys,
IPC names, or the physical default map unless the backwards-compatibility choice
is separately authorized.
