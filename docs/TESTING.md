# Testing

How to run the Nehir test suite, where new tests go, and the policy that
governs the suite's evolution. Applies to human contributors and AI agents
alike.

## Running tests

```bash
mise run test          # full suite (requires Xcode, not just CommandLineTools)
mise run test:compile  # fast check that the test target builds
```

`mise run test` kills any running Nehir instance first, then runs
`IPCServerTests` in its own helper process before the rest of the suite.
Xcode's `swiftpm-testing-helper` can SIGTRAP when the socket-backed
`IPCServerTests` run after AppKit-heavy suites; the split keeps the coverage
without the flake. Don't collapse the two invocations back into one.

Tests are gated in CI (`.github/workflows/ci.yml`, `mise run test` on
`macos-26`). Keep them gated: the suite is a required check, not advisory.

The suite uses **Swift Testing** (`import Testing`), not XCTest. New tests use
Swift Testing.

## When to work on tests

**Defer all test work to the latest stage of the task.** Do not add, modify,
rewrite, delete, move, compile, or run tests until at least one unlock condition
is true:

1. The user confirms the implementation or fix works in their real repro.
2. The user explicitly asks for test work in their feedback.

This is a sequencing rule, not a preservation rule. Existing tests do not decide
what behavior Nehir should keep; they may encode the wrong contract and may need
to be rewritten or deleted after the gate unlocks. The rule delays that work so
it happens after the intended runtime behavior is known.

The gate applies to new features, refactors, and bug fixes alike. "This is a new
feature", "this is only a refactor", "I am only running tests", and "the current
test is wrong" are not exceptions. Reverting or removing a test counts as test
work.

A plan, spec, or delegated task that includes a test phase does **not** unlock
the gate. If neither unlock condition has occurred, defer that phase. Once the
gate unlocks, perform only the test work authorized by the confirmed behavior or
the user's request.

The underlying principle: the user's runtime feedback defines the intended
behavior before tests record it. Writing or running tests earlier spends effort
on an experimental result and creates churn. After unlock, use the suite to
record the confirmed contract, including rewriting or deleting assertions that
encode a different one.

## Where new tests go

**New tests land in small, per-behavior files** named for the behavior under
test — e.g. `Tests/NehirTests/QuickTerminalRefocusTests.swift` — not in the
file named after the handler or engine that happens to contain the code.

The legacy monoliths are **frozen**: do not add tests to

- `Tests/NehirTests/AXEventHandlerTests.swift`
- `Tests/NehirTests/NiriLayoutEngineTests.swift`
- `Tests/NehirTests/RefreshRoutingTests.swift`
- `Tests/NehirTests/MouseEventHandlerTests.swift`
- `Tests/NehirTests/LayoutRefreshControllerTests.swift`
- `Tests/NehirTests/WorkspaceManagerTests.swift`

When a change touches behavior whose existing tests live in a monolith, moving
those tests out into a per-behavior file is in scope for that change.
There is no big-bang splitting project; the monoliths shrink opportunistically.

## Truthfulness rules for new tests

The bar, in one line: **test hooks observe; they do not decide.** Concretely:

1. **No new `ForTests` conditionals in `Sources/` that change a Nehir-owned
   decision.** A test flag must never cause production logic to skip
   reconciliation, lifecycle work, scheduling, fallback, or cleanup
   (`if testFlag { return }` tests a different product).
2. **Fake the OS boundary, not the algorithm.** AX / SkyLight / AppKit
   boundaries are injected as scoped dependencies; Nehir's own logic runs the
   same path in production and tests. Fakes record calls instead of causing
   early returns.
3. **Prefer pure seams.** Where a behavior can be expressed as a pure planner
   (input model → desired operations), test the planner directly and keep the
   effectful reconciler on a single shared path.
4. **Never assert against state that only exists on a test-disabled path.**
   If the observable you want to assert is only recorded when a
   `disables...ForTests` flag is set, the test is validating bookkeeping, not
   the product.
5. **Scope and reset any global provider.** Global mutable `...ForTests`
   statics leak between tests and break parallelism; use scoped isolation
   helpers, and treat direct assignment without a `defer` reset as a review
   defect.

Background and the audited inventory of existing violations live in the
plans branch: `discovery/20260708-test-only-seams-can-make-tests-untruthful.md`.
Existing seams that violate these rules are being removed in that audit's
candidate order; new code must not add more.

## Deleting legacy tests

Rolling, judged deletion is allowed and encouraged. When a legacy test file
(or individual test) blocks a refactor or an upstream port, inspect it before
adapting it: if it asserts mock choreography, `ForTests`-only state, or
internals with no behavioral contract, **delete or rewrite it in the
per-behavior shape as part of that change**, and say so in the commit body.

What is not allowed: bulk deletion of the suite, removing tests from CI, or
deleting a test that encodes a confirmed user repro without replacing the
coverage.

## Tests when porting upstream work

Upstream (BarutSRB/OmniWM) deleted its pre-2026-06 test suite and now ships
small per-behavior XCTest files alongside each feature. When porting upstream
work, **prefer adapting upstream's new test files** (XCTest → Swift Testing,
upstream names → Nehir names) over retrofitting Nehir's legacy files. The
legacy suite no longer has upstream counterparts to diff against.

The full evaluation of upstream's test purge and the rationale for this
policy live in the plans branch:
`discovery/20260712-upstream-test-purge-and-nehir-test-direction.md`.
