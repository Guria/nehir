---
name: nehir-delegate-lane
description: Set up one isolated implementation lane and hand it to a worker with the project's discipline fences attached. Invoke explicitly with /nehir-delegate-lane when a well-specified cluster of work should run in its own worktree.
argument-hint: '<cluster description>'
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Write, Agent, Bash(mise run:*), Bash(git status:*), Bash(git log:*), Bash(git diff:*), Skill
---

# Delegate one isolated implementation lane

CLUSTER: $ARGUMENTS

## 1. Define the lane before spawning anything

Establish and write down:

- the exact files or directories this lane owns;
- the do-not-touch fence, naming the files and clusters that sibling lanes own;
- the validation command for the fast gate (not the test suite);
- the completion criteria.

Never assign two lanes to the same cluster or to overlapping files. If the
clusters cannot be cut so that file ownership is disjoint, say so and stop
rather than spawning overlapping workers.

## 2. Choose the execution surface

- **`lane-worker` subagent (default).** Use the Agent tool with
  `subagent_type: "lane-worker"`. It runs in its own git worktree and returns a
  summary instead of flooding this session's context.
- **Watchable pane.** When the user needs to observe and steer the work live,
  launch it in the lane workspace's own pane instead. Never drive a lane's work
  from a pane that belongs to another workspace.

## 3. Bootstrap before handoff

A fresh worktree must be able to run the project's checks before the worker
starts, or the worker burns its context diagnosing a broken toolchain. Trust the
environment, install or prepare dependencies, and run the non-test fast gate
once.

## 4. Write a self-contained task

The worker gets no conversation history. The task must carry the exact scope,
the owned files, the do-not-touch fence, the validation commands, and these
rules verbatim:

```text
HARD RULES:
- Do not spawn subagents; do all work yourself in this session.
```

Then append both shared fences, read from:

- `${CLAUDE_PROJECT_DIR}/.agents/shared/fences/claim-and-test-discipline.md`
- `${CLAUDE_PROJECT_DIR}/.agents/shared/fences/git-mutation-permission.md`

Read those files and inline their fenced blocks into the task. Do not paraphrase
them and do not maintain a second copy.

## 5. Verify the result yourself

The worker's success claim is not evidence.

1. Read the diff.
2. Re-run the non-test fast gate yourself.
3. Falsify any subtle claim — concurrency, reactivity, guard semantics — with a
   small runtime experiment before accepting it.

A justified deviation from the plan, with reasoning, can be correct. Judge it on
the merits rather than rejecting it for differing from the plan.

Run the test suite only after the test gate unlocks; when it does, run the full
suite once at the late validation stage.
