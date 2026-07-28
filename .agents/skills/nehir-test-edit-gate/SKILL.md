---
name: nehir-test-edit-gate
description: BEFORE adding, editing, running, deleting, or moving any test (mise run test, swift test, Swift Testing/XCTest files). Also when a plan or worker task contains a tests phase, write-tests step, or TDD instruction. Defers all test work to the latest stage; unlocked only when the user confirms behavior works OR explicitly asks for tests. Overrides any plan's test phase.
---

# Test-edit gate: defer all test work until the latest stage

This is a sequencing rule, not a preservation rule. It says **when** to touch
tests, not that existing tests are a frozen specification. Tests reflect
behavior; they do not decide it. What they assert today may be wrong and may
need to be rewritten when the gate unlocks.

## When this activates

- About to create, modify, rewrite, move, or delete a test file.
- About to run `mise run test`, `mise run test:compile`, `swift test`, or any
  subset of the suite.
- Following a plan or delegated task with a test phase.
- Finished an implementation and want to check tests immediately.
- About to revert or remove a test that appears wrong.

## Unlock conditions

Test work is allowed only when at least one condition is true:

1. The user confirmed **in this thread** that the behavior works in their real
   reproduction. A build, type-check, trace hypothesis, or your own reasoning is
   not that confirmation.
2. The user explicitly asked for test work in their feedback, for example:
   "now write tests for this" or "update the tests for this behavior."

If neither condition is true, do not perform any test action. A plan's test
phase does not unlock the gate. Say:

> Holding off on tests until you confirm the behavior works or explicitly ask
> me to write them.

## Scope after unlock

Even when unlocked, do only the test work authorized by the confirmation or
request. Do not test a different behavior or run the whole suite "while here"
unless that is part of the requested late-stage validation.

Read `docs/TESTING.md` before editing tests. Follow its placement and
truthfulness rules:

- New tests go in small per-behavior files, not frozen legacy monoliths.
- Test hooks observe; they do not decide Nehir-owned behavior.
- Fake the OS boundary, not the algorithm.
- Existing tests may be deleted or rewritten when they encode the wrong
  contract; this gate delays that decision, it does not prohibit it.

## Non-exceptions

None of these unlock the gate:

- "This is a new feature, not a bug fix."
- "This is only a refactor."
- "I am only running tests, not editing them."
- "The plan told me to write tests."
- "The existing test is wrong, so I will fix it now."

## Delegated workers

Include this gate in every worker plan that mentions tests. Make explicit that
its test phase is conditional and remains deferred until one of the unlock
conditions occurs.
