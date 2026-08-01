---
name: nehir-capture-landed-state
description: Record what actually landed on main after a change was reviewed and merged — prove the merge, capture the landed state including deviations and leftovers, then update and move the affected documents on the plans branch. Invoke explicitly with /nehir-capture-landed-state once a change is merged.
argument-hint: '[#NN] [merge commit, PR, or branch] [what changed during review]'
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Edit, Write, Skill, Bash(git log:*), Bash(git show:*), Bash(git diff:*), Bash(git status:*), Bash(git merge-base:*), Bash(git branch --contains:*), Bash(git tag --contains:*), Bash(git worktree list:*), Bash(gh pr view:*), Bash(gh pr list:*), Bash(gh issue view:*), Bash(gh issue list:*)
---

# Capture the landed state

CHANGE: $ARGUMENTS

The work is merged; this run is the record of it. The documents on the plans
branch still describe an intention. Replace that intention with what `main`
actually contains.

If the arguments do not identify the change, find it from the working context —
the branch, the plan being implemented, the ticket — and state which change you
resolved before touching any document.

## 1. Prove it landed before writing that it landed

1. Locate the commits on `main`. Search by ticket or subject with `git log`, or
   read the merge commit off the PR with `gh pr view <N>`.
2. Confirm containment: `git merge-base --is-ancestor <sha> main`, or
   `git branch --contains <sha>`. A merged PR page is not proof that the local
   `main` you are reading contains the commit.
3. Record the release that carries it: the first tag from
   `git tag --contains <sha>`. That tag is the landed version.
4. If the commit is not an ancestor of `main` — the branch is unmerged, the
   merge is local and unpushed, or the change was squashed under a subject you
   cannot match — say exactly that and stop.

Never write `landed`, `shipped`, or `merged` about a commit you have not located
on `main`. When part of the work landed and part did not, name each part
separately rather than letting one word cover both.

## 2. Reconstruct the landed state, not the planned one

Read the whole merged range, not just the first implementation commit. Review
fixes, follow-up commits driven by later traces, test commits, and lint/format
commits pushed after the merge are all part of what shipped.

Capture, with evidence:

- **Every commit that carries the change** — short sha and subject.
- **Deviations from the plan, and why.** A deviation is a finding, not a
  failure. When a document's hypothesized mechanism turned out wrong but the
  symptom is gone, record both facts and keep them distinguishable.
- **What did not ship** — deferred phases, dropped heuristics, accepted residual
  risk, anything the plan proposed that the implementation left out.
- **The pitfalls.** Retired hypotheses, dead ends, and the problems that cost
  iterations belong in the record; they are what makes the document worth
  keeping.
- **The release note** — the Changesets fragment that shipped and the
  contributor attribution recorded in it. Note its absence if there is none.
- **The tests that landed**, by file.
- **The gate result** as a named command and its outcome, for example
  `mise run check` passed with N tests in M suites. Not "all green".

When the change landed as part of a larger merge, or the fix arrived through a
different change than the one the document scoped, say so explicitly.

## 3. Update every affected document

The documents live on the `plans` branch worktree — never in the source
checkout. Find it with `git worktree list`. Its folders sit at that worktree's
root: `planned/`, `completed/`, `discovery/`, `noop/`, not under `docs/plans/`.
Read that worktree's own `AGENTS.md` and follow it.

1. Find every document that owns part of this work: the plan, its companion
   discovery, cluster and cross-link documents, and any document whose status
   the landing invalidates.
2. Rewrite the status line in place, in the branch's established shape:

   ```
   **Status:** completed — shipped on `main` in `<sha>` ("<commit subject>"),
   merged <YYYY-MM-DD> via PR #NN, contained in `<tag>`. Moved from `planned/`
   to `completed/` on <YYYY-MM-DD>.
   ```

3. Move the document to the folder matching its state: shipped or superseded to
   `completed/`, a verdict of no-op / already fixed / duplicate / not applicable
   to `noop/`. Move the companion discovery too when the landing closes it. A
   completed document left in `planned/` is the failure this run exists to
   prevent.
4. Repair the relative cross-links the move breaks. A document in `completed/`
   reaches a discovery as `../discovery/<name>.md`, and both ends of a link
   change when both files move. Verify each link you touched resolves to a file
   that exists.
5. Convert future-tense prose about work that is now on `main`. A shipped
   document should not read as a proposal.

## 4. Leftovers become their own document

Genuinely out-of-scope follow-up work becomes a new discovery in `discovery/`,
cross-linked to the completed document — not a TODO buried inside it.

Do not open a new document for a symptom that survived the change. An
unconfirmed or failed fix is `/nehir-retry-with-new-trace`, which updates the
existing document in place.

## 5. Claims and conventions

Load `nehir-claim-discipline` and `nehir-doc-review` and apply both before
saving.

- `landed` / `shipped` / `merged` require the containment evidence from step 1.
- `fixed` / `works` / `resolved` require the user's confirmation in their real
  reproduction. A merge is not that confirmation by itself. When the user did
  confirm the repro before the merge, say so and name what they confirmed.
- A bare `#nnn` means this repository's tracker. Upstream tickets are always
  `BarutSRB/OmniWM#nnn`, never `OmniWM #nnn` or bare `#nnn`.
- Anchor every date and comparison to a commit, tag, or named event. No
  `current`, `recent`, or `latest`.

## Fences

- **No `Sources/` edits.** This run is documentation. If reading `main` reveals
  a real defect, report it and stop rather than fixing it here.
- **No test work.** Recording which tests landed is documentation and is fine.
  Writing, moving, or deleting tests needs the user's explicit ask;
  `nehir-test-edit-gate` applies otherwise.
- **Git is gated.** `nehir-git-mutation-gate` applies to both worktrees. Ask
  before each distinct action — staging and committing are two. Plans-branch
  commit subjects are plain English describing the record, for example
  "Record that the hide-empty focused-workspace fix shipped". Read-only
  inspection needs no permission; a `git -C <plans worktree> …` call may still
  raise a prompt, which is intended.
- **The issue is the user's to close.** Report whether the nehir issue is still
  open and propose closing it. Do not close it yourself unless asked.

## Exit condition

Every affected document names the commits on `main` that carry the change, the
tag containing them, the deviations, the leftovers, and the gate result; sits in
the folder matching its state; carries a dated status line; and its cross-links
resolve. Changes are left uncommitted unless the user authorized a commit.
