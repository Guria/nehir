---
name: nehir-solution-robustness
description: BEFORE presenting or finalizing a fix, especially layout, timing, configuration, serialization, or monitor-geometry logic. Activate when introducing a hardcoded number/timing, boolean behavior flag, special case, migration/compatibility shim, or scope beyond the request.
---

# Solution robustness: fix the mechanism, not one symptom

A solution should express the underlying invariant and remain correct across
the relevant input space. A value or branch that happens to repair one repro is
not sufficient evidence of a robust fix.

## Pre-finalization checklist

### 1. Derive values

Every literal number or timing that controls behavior needs a source:

- a system constant;
- a measured and documented quantity;
- a value derived from inputs;
- an explicitly named configuration value.

If a value was chosen by feel because it made one repro pass, stop and derive or
measure it. Document genuinely empirical constants.

### 2. Model concepts instead of accumulating flags

Before adding a boolean that switches behavior, ask whether the code is really
modeling distinct strategies, states, or capabilities. Prefer composition, a
small type, or a named policy when that expresses the concept more directly.
A boolean is acceptable only when it genuinely models a binary fact rather
than coordinating unrelated behavior through conditionals.

### 3. Fix the shared mechanism

The visible symptom may be downstream of the fault. Check whether the proposed
solution holds for other windows, monitors, workspaces, or input shapes that use
the same mechanism. If it only benefits the one case examined, it is likely a
symptom patch.

### 4. Do not migrate unreleased state

Migration and compatibility code are for schemas or behavior that users already
have in shipped releases. If the state has never shipped, write the intended
shape directly.

### 5. Do not assume backward compatibility

Preserve, break, or migrate existing behavior only when repository instructions
or the user specify which is required. If the choice changes the implementation
and no rule defines it, ask before proceeding.

### 6. Keep scope explicit

Do not bundle unrelated refactors, renames, or logic changes into the task. Note
valuable follow-up work separately.

### 7. Exercise the input space

For layout and geometry, reason through at least the boundary cases relevant to
the algorithm: one item, multiple items, a larger count, and different monitor
or window dimensions. For state/lifecycle logic, check entry, steady state,
interruption, and cleanup.

## Exit condition

The proposal states its invariant, explains its constants, covers relevant
boundary cases, introduces no unjustified compatibility or migration behavior,
and stays within scope. Otherwise report it as a draft or hypothesis rather
than a completed solution.
