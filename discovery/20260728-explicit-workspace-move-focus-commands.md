# Discovery: explicit follow/stay workspace-move commands

Status: open discovery — the product redesign (Variant A) is not yet started.
Nehir currently encodes two valid per-action intentions — move and follow, or
move and stay — as one command family whose meaning depends on global mutable
state. The preferred direction is **Variant A**: replace that mode with explicit
`Follow` and `Stay` command families, then migrate existing bindings to the
family matching the user's saved setting.

The underlying consistency bug this document leans on — only two of five
workspace-move paths honoring `focusFollowsWindowToMonitor`, plus source-scroll
and stale-focus-handoff defects — has shipped on `main` as `62d54e16`
("Honor the follow-focus setting on every workspace move") on 2026-07-28. That
fix makes the current setting-based contract honest but does not change the
command abstraction this document argues against.

Verified against Nehir `main` at `64e0b98c` on 2026-07-28, with the shipped
focus-handoff work recorded at `62d54e16`. This document changes no source files.

## Executive conclusion

`focusFollowsWindowToMonitor` is a real, persisted, user-visible setting:

- `SettingsStore` stores and saves it
  (`Sources/Nehir/Core/Config/SettingsStore.swift:37-39`);
- the default is `false`
  (`Sources/Nehir/Core/Config/SettingsExport.swift:128-135`);
- `settings.toml` exports it as `focus.followsWindowToMonitor`
  (`Sources/Nehir/Core/Config/CanonicalTOMLConfig.swift:289-293`);
- Settings presents it as **Follow Window to Workspace**
  (`Sources/Nehir/UI/BehaviorSettingsTab.swift:40-50`);
- a bindable command toggles it at runtime
  (`Sources/Nehir/Core/Input/HotkeyCommand.swift:98-100`,
  `Sources/Nehir/Core/Controller/CommandHandler.swift:223-229`,
  `Sources/Nehir/Core/Config/HotkeyConfigMapping.swift:140-143`).

The runtime toggle means the choice is already not strictly a configuration-time
preference. It instead makes workspace moves modal: the same command and hotkey
can mean either “move and stay” or “move and follow” depending on hidden global
state. A user who normally stays but wants to follow one move must toggle the
mode, move, then toggle it back. IPC clients have the same problem and must read
or mutate shared state before issuing an otherwise incomplete command.

The two intentions should be atomic commands:

- **move and stay** — transfer the window/column, keep the user's active workspace;
- **move and follow** — transfer it, activate the destination, focus the moved
  window there.

Both should cover every existing move-to-workspace shape: adjacent window,
adjacent column, numbered window, numbered column, and numbered workspace on an
adjacent monitor. The move algorithm remains shared; only the focus policy is
explicit at command dispatch.

A lack of spare default hotkeys is not a blocker. `ActionCatalog` already ships
many commands as `.unassigned`, including adjacent and numbered column moves and
all cross-monitor numbered moves
(`Sources/Nehir/Core/Input/ActionCatalog.swift:301-375`). One family can retain
the migrated/default bindings while the other remains unassigned and available
through Settings, the command palette, TOML, and IPC.

## Current command model

### One command id carries two meanings

`HotkeyCommand` exposes one case per destination shape:

```swift
case moveToWorkspace(Int)
case moveWindowToWorkspaceUp
case moveWindowToWorkspaceDown
case moveColumnToWorkspace(Int)
case moveColumnToWorkspaceUp
case moveColumnToWorkspaceDown
case moveWindowToWorkspaceOnMonitor(workspaceIndex: Int, monitorDirection: Direction)
```

These cases are declared at
`Sources/Nehir/Core/Input/HotkeyCommand.swift:13-18,73-75`.
`CommandHandler.performCommand` forwards each directly to
`WorkspaceNavigationHandler` without carrying a focus policy
(`Sources/Nehir/Core/Controller/CommandHandler.swift:77-88,175-181`). The
navigation handler therefore decides the post-move meaning from
`settings.focusFollowsWindowToMonitor` rather than from the command itself.

On current `main`, numbered-window and cross-monitor moves read the setting
inside `WorkspaceNavigationHandler`
(`Sources/Nehir/Core/Controller/WorkspaceNavigationHandler.swift:869-915,1021-1093`).
The adjacent-window, adjacent-column, and numbered-column paths do not yet read
it (`:694-862`); that inconsistency is the separate bug addressed by the
workspace-move focus-handoff fix that shipped as `62d54e16`.

The shipped fix (`62d54e16`) makes the current contract consistent: all move
paths use one `finishWorkspaceMove(...)`, stop source-monitor scroll animation,
and recompute/validate post-layout focus. Its policy enum is already the natural
seam for the product redesign:

```swift
private enum WorkspaceMoveFocusPolicy {
    case configured
    case staySource
}
```

The helper receives that policy in
`Sources/Nehir/Core/Controller/WorkspaceNavigationHandler.swift`, and
`.configured` still reads the global setting there. A follow-up can preserve the
helper and focus-safety work while changing the policy to explicit `.follow` /
`.stay` values supplied by `CommandHandler`.

### The command is modal even though the setting is persisted

The UI wording presents `focusFollowsWindowToMonitor` as a general navigation
preference. The bindable toggle proves it is also expected to change during a
session. This creates a hidden-mode interaction:

1. the move command id and hotkey stay constant;
2. a separate command mutates global state;
3. subsequent move commands silently change meaning;
4. nothing in the move command's title or IPC name states the active meaning.

For keyboard use, a one-off opposite action takes three commands: toggle, move,
toggle back. For IPC, two clients can interfere by changing the same setting.
An atomic command avoids both problems.

## Target command model

The command layer should carry an explicit focus policy. The exact Swift shape
belongs in planning, but the semantics should be equivalent to:

```swift
enum WorkspaceMoveFocusPolicy {
    case follow
    case stay
}
```

Each user-facing action should identify one policy in its command value or map
to one at dispatch. Avoid one generic command whose execution still consults
`SettingsStore`.

The user-facing names should be symmetrical. Neither behavior is the special or
“silent” form:

- `Move Window to Workspace 3 and Follow`
- `Move Window to Workspace 3 and Stay`
- `Move Window to Workspace Up and Follow`
- `Move Window to Workspace Up and Stay`
- `Move Column to Workspace 3 and Follow`
- `Move Column to Workspace 3 and Stay`

Possible TOML key families:

```toml
[workspace]
moveToFollow.3 = "..."
moveToStay.3 = "..."
moveColumnToFollow.3 = "..."
moveColumnToStay.3 = "..."
```

A nested naming scheme is also viable. The requirement is that the key and
command title state the full intention without consulting another setting.

## Hotkey capacity is not the constraint

`ActionCatalog` already separates action availability from default assignment:

- numbered window moves have assigned defaults
  (`Sources/Nehir/Core/Input/ActionCatalog.swift:145-162`);
- adjacent window moves have assigned physical-Hyper defaults (`:301-316`);
- adjacent column moves are unassigned (`:317-328`);
- numbered column moves are generated as nine unassigned actions (`:331-340`);
- cross-monitor numbered moves are generated as 36 unassigned actions
  (`:364-375`).

`HotkeyConfigMapping.NumberedGroup` already expands one human-readable numbered
family into nine internal ids
(`Sources/Nehir/Core/Config/HotkeyConfigMapping.swift:15-47`). Adding `Follow`
and `Stay` numbered groups increases the catalog/config surface but requires no
new hotkey mechanism.

The product does not need defaults for both families. Migration can keep each
user's existing chords on one family. The alternate family can remain
unassigned. Users who need both can bind only the subset they use — for example,
`Stay` for numbered destinations and `Follow` only for adjacent up/down moves.

## Variants

### Variant 0 — retain the global setting

Keep the model after the focus-handoff fix: every normal workspace-move command
uses `focusFollowsWindowToMonitor`; the workspace-bar explicit-token move remains
non-following.

**Advantages**

- no command, config, UI, or IPC migration;
- one preference changes all move commands;
- the focus-handoff fix (`62d54e16`) already makes the behavior internally consistent.

**Costs**

- a move command remains incomplete without hidden global state;
- one-off opposite behavior requires toggle → move → toggle;
- the same hotkey and IPC name have two meanings;
- scripts must inspect or mutate shared state;
- two clients can race through the setting.

Choose this only if follow/stay is intentionally a stable user preference rather
than a per-action intention.

### Variant A — explicit commands with behavior-preserving migration (preferred)

Add `Follow` and `Stay` action families. Migrate every existing move binding to
the family matching the saved `focusFollowsWindowToMonitor` value, preserving
the physical chord. Remove the setting and its toggle after migration. Leave the
other family unassigned.

Example:

- old setting `false` + `moveToWorkspace.3 = Hyper+3`
  → `moveToWorkspaceStay.3 = Hyper+3`;
- old setting `true` + the same binding
  → `moveToWorkspaceFollow.3 = Hyper+3`.

**Advantages**

- clean final model with no hidden mode;
- existing users retain observed behavior and chords;
- both intentions can be bound simultaneously;
- command palette and IPC actions are self-describing;
- the helper receives an explicit policy and no longer reads settings.

**Costs**

- migration must coordinate `settings.toml` and `hotkeys.toml`;
- all command surfaces must gain the new families;
- the old setting and toggle need removal and release-note explanation;
- malformed, absent, or partially customized configs need defined fallback
  behavior.

This is the best balance: preserve behavior, remove the wrong abstraction, and
avoid a permanent compatibility layer.

### Variant B — explicit commands plus legacy configured aliases

Add both explicit families but retain the old generic commands and global
setting. Existing configs keep working unchanged; new users bind explicit
commands. Mark generic commands/settings as legacy and remove them in a later
release.

**Advantages**

- lowest immediate compatibility risk;
- users can migrate gradually;
- explicit actions become available without a cross-file migration on day one.

**Costs**

- every operation has three semantics: Follow, Stay, and Configured;
- the hidden mode and IPC race remain for legacy commands;
- Settings, palette, docs, and tests must explain near-duplicates;
- a temporary layer can become permanent without a removal deadline.

Use this only if direct migration is too risky. A plan must name the release or
condition that removes the legacy layer.

### Variant C — explicit commands with a clean compatibility break

Remove the setting immediately. Assign one fixed meaning to old command names
and add a second family for the other meaning. Do not migrate user bindings.

**Advantages**

- smallest implementation and clean model immediately;
- no migration state or temporary aliases.

**Costs**

- users whose saved preference differs from the chosen meaning silently change
  behavior;
- the failure is disruptive: focus moves to the wrong workspace or fails to
  follow, rather than merely changing a label;
- manual TOML repair and prominent release notes are required.

This is acceptable only under an explicit decision that the relevant release
may break existing behavior. No such authorization is assumed here.

### Hybrid — one-shot modifier or inverse action

Keep a primary behavior and let an extra modifier invert it for one invocation.
This may be a useful UI convenience, but it should sit on top of two atomic
commands rather than replace them.

**Advantages**

- quick one-off opposite behavior;
- fewer prominent defaults.

**Costs**

- modifier discovery is poor;
- many workspace bindings already use dense modifier chords;
- Carbon hotkey registration still treats the modified chord as a separate
  binding;
- command palette and IPC still need explicit Follow and Stay actions;
- “invert configured behavior” reintroduces hidden state.

Do not use inversion as the command model. It can be an optional binding affordance
once explicit commands exist.

## Preferred Variant A migration boundary

The setting and hotkey overrides live in separate files:

- `focus.followsWindowToMonitor` is in `settings.toml`;
- command assignments are in `hotkeys.toml`
  (`SettingsFilePersistence.hotkeysFileName`,
  `Sources/Nehir/Core/Config/SettingsFilePersistence.swift:41`).

Current settings migrations are file-oriented descriptors and transformations
(`Sources/Nehir/Core/Config/SettingsMigrationRegistry.swift:12-77,89-123`).
`HotkeysTOMLCodec` separately resolves human-readable keys to internal ids and
applies valid overrides over catalog defaults
(`Sources/Nehir/Core/Config/HotkeysTOMLCodec.swift:190-225`).

A plan must choose one migration mechanism after inspecting load/save ordering:

1. **Cross-file migration:** back up both files, read the saved setting, rewrite
   old hotkey keys to the matching explicit family, remove the setting, then
   write both atomically as one logical migration.
2. **Read-time compatibility aliases:** decode old hotkey keys into the matching
   explicit command family using the loaded legacy setting; export only new keys
   on the next save; remove the compatibility reader after a defined period.
3. **Legacy command bridge:** Variant B, only if coordinating both files is not
   reliable enough for Variant A in one release.

Migration must preserve explicit user chords, including `Unassigned`; it must not
replace them with new defaults. When the old setting is absent or invalid, use
its shipped default (`false`) and migrate to `Stay`. If a new explicit key and an
old generic key both exist, the explicit key should win and the migration should
report the conflict rather than overwrite it silently.

## Affected product surfaces

A complete plan must cover these surfaces together:

- **Command model:** `Sources/Nehir/Core/Input/HotkeyCommand.swift`
- **Dispatch:** `Sources/Nehir/Core/Controller/CommandHandler.swift`
- **Shared move completion:**
  `Sources/Nehir/Core/Controller/WorkspaceNavigationHandler.swift`
- **Action ids, titles, search terms, and default/unassigned bindings:**
  `Sources/Nehir/Core/Input/ActionCatalog.swift`
- **TOML key mapping and numbered groups:**
  `Sources/Nehir/Core/Config/HotkeyConfigMapping.swift`
- **Settings removal/migration:** `SettingsStore.swift`, `SettingsExport.swift`,
  `CanonicalTOMLConfig.swift`, `SettingsMigrationRegistry.swift`, and the
  Behavior Settings UI
- **IPC names, arguments, manifest, and routing:**
  `Sources/NehirIPC/IPCModels.swift`, `IPCAutomationManifest.swift`, and
  `Sources/Nehir/IPC/IPCCommandRouter.swift`
- **Documentation and release notes:** explain that existing chords keep their
  old observed behavior but the global toggle becomes explicit actions.

The IPC surface is not incidental. It currently exposes generic names such as
`move-to-workspace`, `move-column-to-workspace`, and
`move-to-workspace-on-monitor`, plus
`toggle-focus-follows-window-to-monitor`
(`Sources/NehirIPC/IPCModels.swift:252-265,300`). Explicit IPC actions remove the
need for scripts to coordinate through shared global state.

## What the existing focus-handoff fix should preserve

This product redesign must not reopen the bugs addressed by `62d54e16`. Keep:

1. one shared finish path for all move shapes;
2. unconditional source-monitor scroll-animation stop;
3. source selection recovery;
4. target viewport preparation;
5. post-layout focus token recomputation;
6. active-workspace and entry-membership verification before focus;
7. the workspace-bar explicit-token move's intentional `Stay` semantics.

Only the policy source changes: from `SettingsStore` inside the helper to the
explicit command dispatched by the caller.

## Verification scenarios for a future implementation

After the user confirms an implementation in the real app, tests should cover
both policies for each move shape:

1. focused window → adjacent workspace;
2. column → adjacent workspace;
3. focused window → numbered workspace;
4. column → numbered workspace;
5. focused window → numbered workspace on another monitor.

For every shape:

- `Follow` activates the destination and focuses the moved window;
- `Stay` leaves the source workspace active and focuses a valid source window;
- source scroll animation stops under both policies;
- switching elsewhere before post-layout completion prevents stale focus theft.

Migration verification must start from both legacy setting values and confirm
that existing physical chords map to the matching explicit family without
changing user-visible behavior.

Per repository policy, do not add or modify tests before the user confirms the
implementation in a real reproduction.

## Recommendation

Choose **Variant A**: two explicit command families with behavior-preserving
migration based on the saved setting.

Both behaviors are valid, but that does not make them a global preference. It
makes them two valid intentions that a user may need at different moments. The
command should encode the intention; configuration should only decide which
physical trigger invokes it.

The next planning step should first resolve the cross-file migration mechanism
and exact action/TOML/IPC names. It should then split implementation by surface
while preserving the shared move-completion helper and focus-safety invariants.

## Follow-up status (2026-07-28)

The setting-consistency work this discovery leans on has shipped:

- `origin/main` contains `62d54e16` ("Honor the follow-focus setting on every
  workspace move"), which routes all five workspace-move paths through one
  `finishWorkspaceMove(...)`, stops the source-monitor scroll animation on every
  path, and validates post-layout focus before applying it, including a
  navigation-generation guard in `WindowActionHandler.navigateToWindowInternal`.
  Verified against `main` via `git show --stat 62d54e16`.

The product redesign itself — explicit `Follow` / `Stay` command families with
behavior-preserving migration (Variant A) — is **not started**. This document
remains an open discovery and is the starting point for that work.
