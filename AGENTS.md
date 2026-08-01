# AGENTS.md

Instructions for AI agents working in this repository.

## Shared agent assets

`.agents/` holds the skills, fence text, and gate hook scripts for this
repository; `.agents/README.md` documents them. Five gate skills activate on
their own at the moment their rule applies (tests, git mutations, success
claims, fix robustness, durable documents). Six workflows run only when invoked
as slash commands: `/nehir-bug-discovery`, `/nehir-retry-with-new-trace`,
`/nehir-delegate-lane`, `/nehir-finalize-change`, `/nehir-review-triage`,
`/nehir-capture-landed-state`. The rules below remain authoritative; the skills
are how they reach the point of decision.

## Plans branch instructions

When working with planning documents in the dedicated plans-only worktree/branch,
read that worktree's `AGENTS.md` first and follow it. The plans branch has its
own document layout and stricter durable-doc rules (for example, no local
machine-specific paths in discovery/planning docs).

## Tests

Read `docs/TESTING.md` before adding, moving, or deleting tests. The hard
rules, in short:

- **Defer all test work to the latest stage.** Do not add, modify, rewrite,
  delete, move, compile, or run tests until the user either confirms the
  behavior works in their real repro or explicitly asks for test work. This is
  a sequencing rule, not a preservation rule: existing tests may encode the
  wrong contract and may be rewritten or deleted after the gate unlocks. The
  gate applies to new features, refactors, and bug fixes; a plan's test phase
  does not unlock it. Read `docs/TESTING.md` for the full policy.
- **New tests go into small per-behavior files.** The legacy monoliths
  (`AXEventHandlerTests.swift`, `NiriLayoutEngineTests.swift`, and the others
  listed in `docs/TESTING.md`) are frozen — never append tests to them.
- **Test hooks observe; they do not decide.** Do not add `ForTests`
  conditionals in `Sources/` that change a Nehir-owned decision (skip
  reconciliation, lifecycle, scheduling, fallback, or cleanup). Fake the OS
  boundary, not the algorithm.
- Run the suite with `mise run test`; keep it gated in CI.

## Temporary bug-tracing instrumentation

When bug-tracing code is built in a dedicated throwaway worktree and will be
removed before finalization, **never gate it** behind a feature flag, environment
variable, verbosity setting, or any other opt-in control. Emit the temporary
diagnostics unconditionally to the exact trace/capture sink the user will
inspect.

Before asking the user to reproduce the bug, verify that a known instrumentation
marker appears in the actual captured artifact. Seeing it in another logging
subsystem (for example, `os_log` when the user will provide a runtime-trace file)
does not count.

## Changesets

For user-visible changes, create a Changesets release-note fragment with:

```bash
mise run changeset <patch|minor|major|none> "User-facing summary"
```

Use `patch` for bug fixes, `minor` for new user-facing features, `major` for
breaking changes, and `none` for release-note-only changes. Add contributors
when needed with `--contributors handle1,handle2`. Issue reporters count as
contributors; include their GitHub handle when a change fixes a reported issue.
Mention the ticket/issue number in the changeset summary when one was involved.

Reference **only the nehir repo's own ticket number** (e.g. `Fixes #nnn`) in
changesets and commit messages — a bare `#nnn` auto-links to this repository on
GitHub, so it must point at the nehir issue, not upstream. **Do not** cite
upstream tickets (e.g. `OmniWM #nnn`, `BarutSRB/OmniWM#nnn`) in changesets or
commit messages; track upstream provenance in the nehir ticket body instead,
where it belongs.

In places where upstream tickets *are* cited (issue bodies, discovery and
planning documents), always use the full cross-repo form `BarutSRB/OmniWM#nnn`
— never `OmniWM #nnn` or bare `#nnn`. Bare `#nnn` means this repo's own
tracker; the two trackers share overlapping number ranges, so only the
`owner/repo#nnn` form is unambiguous.

Additional changeset rules:

- **Never guess the contributor or reporter.** Look up the actual GitHub handle
  from the nehir issue or PR before adding `--contributors`. Issue reporters
  count as contributors.
- **Choose the bump from the change, not the current version number.** Use
  `patch` for a user-facing fix, `minor` for a user-facing feature, `major` for
  a breaking change, and `none` only for release-note-only changes.
- **Write user-facing copy.** Describe the symptom and outcome in plain language;
  keep implementation detail and root-cause analysis in the ticket or discovery
  document.
- **Do not create duplicate fragments.** Before creating a changeset, check
  whether an existing fragment covers the same change. Update that fragment
  instead, preserving any contributor attribution already recorded there.

## Commit messages

Do not use Conventional Commits formatting (`fix:`, `feat:`, `chore:`, etc.).
Use concise plain-English commit subjects instead.

As with changesets, reference only the nehir repo's own ticket number (`#NN`)
never upstream tickets — upstream provenance lives in the ticket body.

## Git mutations require explicit per-action permission

Never mutate git state unless the user has explicitly approved that exact
action. This includes staging, committing, pushing, amending, restoring,
resetting, reverting, stashing, rebasing, merging, cherry-picking, creating or
switching branches, deleting branches, tagging, and `git rm`.

Permission does not chain: approval to commit does not authorize staging,
pushing, amending, or another commit. Approval in another thread or context does
not carry over.

Changes the user created in the working tree or index are inviolable. Do not
stage, unstage, restore, revert, reorder, or otherwise alter them, even to
"clean up" or undo an action you think was mistaken. If an unauthorized mutation
occurs, report it; do not auto-undo it without another explicit instruction.
Read-only commands such as `git status`, `git diff`, `git log`, and `git show`
do not require permission.

## Verification before success claims

Match every claim to the evidence actually available:

- Source, trace, screenshot, and command output establish **observations**.
- A build or check establishes only that the named command passed.
- A code edit establishes only that the code changed.
- Runtime behavior is `fixed`, `working`, or `resolved` only after the user
  confirms it in their real reproduction.

Report mechanically verified facts plainly and precisely, but do not promote
them into behavioral success. Until runtime confirmation, use calibrated terms
such as `hypothesis`, `implemented but unconfirmed`, or `candidate cause`, and
state the concrete observation that would falsify the claim. Never assert that
an artifact contains evidence you have not read.

## Solution robustness over hacks

Fix the shared mechanism, not one visible symptom. A solution must state the
invariant it enforces and remain correct across the relevant input space.

- Derive behavioral numbers and timings from inputs, system constants, named
  configuration, or documented measurements. Do not choose literals because
  they repair one reproduction.
- Before adding a boolean behavior flag, decide whether it is actually modeling
  distinct states, strategies, or capabilities. Prefer composition or a named
  policy when that expresses the concept directly.
- Check relevant boundary cases. For layout/geometry this includes different
  item counts and monitor/window dimensions; for lifecycle code it includes
  entry, steady state, interruption, and cleanup.
- Do not write migration or compatibility code for state that has never shipped.
- Do not assume backward compatibility. If preserve/break/migrate affects the
  implementation and no rule defines it, ask the user.
- Keep unrelated refactors and logic changes out of scope; propose them
  separately.

## Discovery documents: do not reference trace log filenames

When writing discovery / investigation documents (under `docs/plans/discovery/`,
or anywhere that records a runtime bug), **do not reference trace log filenames**
(e.g. `runtime-trace-1781525802769-1781525820832.log`, line numbers inside a
log, "trace 1 / trace 2", or relative paths into `~/.local/state/nehir/traces/`).

**Why:** trace logs are machine-local and ephemeral. They will not exist later,
on another machine, or in CI — so any finding that depends on re-opening one
becomes unverifiable and effectively useless.

**Do instead — inline the evidence into the document itself.** A discovery must
be self-contained. Copy the specific values, events, or fields that prove the
finding directly into the prose:

- Relevant log lines / events, quoted as text (not as a file reference).
- The concrete numeric state that demonstrates the bug — e.g.
  `currentViewStart=3186.1 → targetViewStart=1259.5`,
  `isWorkspaceActive=false`, `interactionMonitor=display 2`, `didReveal=true`.
- Window tokens, pids, workspace/monitor identifiers needed to follow the
  reasoning, restated where they matter (not "see the log").
- The topology/initial state required to reproduce (which app on which monitor,
  which workspace was focused, etc.).

The goal is that the document can be read and acted on with no access to any
captured log. If a detail is worth citing from a trace, it is worth copying into
the document.

Code citations (file + line, e.g. `AXEventHandler.swift:1790`) are fine and
encouraged — they point at durable source, not ephemeral runtime output.

Durable documents (discoveries, plans, completed write-ups, and tickets) must
also be self-contained and stable outside the author's session:

- Do not include absolute home paths, worktree paths, Downloads paths, hostnames,
  or other machine-specific locations.
- Avoid unanchored relative language such as `current`, `new`, `recent`,
  `previous`, or `latest`. Name the version, commit, state, event, or transition
  that anchors the comparison.
- Back factual claims with inlined evidence, a durable code citation, or an
  explicit `hypothesis` label. Narrow or remove statements the evidence does not
  establish.
- Use `fixed`, `works`, and `resolved` only after user-confirmed runtime behavior;
  otherwise use precise states such as `observed`, `proposed`, `implemented but
  unconfirmed`, or `under investigation`.
