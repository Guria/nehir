---
name: nehir-finalize-change
description: Finalize a Nehir change — produce or update the Changesets fragment and prepare the commit message — without performing any unauthorized git mutation. Invoke explicitly with /nehir-finalize-change once the implementation is done.
argument-hint: '[nehir issue number]'
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Edit, Write, Bash(mise run changeset:*), Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(gh issue view:*), Bash(gh pr view:*), Skill
---

# Finalize a Nehir change

TICKET: $ARGUMENTS (a nehir issue number, or empty when there is none)

## Git actions

Load the `nehir-git-mutation-gate` skill and apply it for the whole run.

- Do not mutate git until the user authorizes that exact action.
- Permission to commit does not authorize staging, push, amend, or a second
  commit.
- Never alter changes the user staged.
- Commit subjects use concise plain English. Never Conventional Commits
  (`fix:`, `feat:`, `chore:`).
- Reference only this repository's ticket as `#NN`. Upstream provenance belongs
  in the nehir issue body, never in a commit message or changeset.
- Include the required `Co-Authored-By` trailer.

## Changeset

1. Check whether an existing fragment already covers this change. If one does,
   update it and preserve any contributor attribution recorded there. Do not
   create a duplicate.
2. Create or update the fragment through `mise run changeset`.
3. Choose the bump from the change itself, not from the version number:
   `patch` for a user-facing fix, `minor` for a user-facing feature, `major`
   for a breaking change, `none` for release-note-only.
4. Write user-facing copy: the symptom and the outcome in plain language.
   Implementation detail and root-cause analysis stay in the ticket or the
   discovery document.
5. Look up the actual GitHub handles of the reporter and contributors from the
   nehir issue or PR. Never guess a handle. Issue reporters count as
   contributors.
6. Mention the nehir ticket number when one exists.

## Claims

Load `nehir-claim-discipline`. Report what was mechanically verified — a
changeset file was written, a named check passed — and leave runtime behavior
unconfirmed until the user verifies it in their own reproduction.

## Fences

- Do not touch tests. `nehir-test-edit-gate` applies unless the user has
  already unlocked it in this thread.
- Stop and ask before each distinct git action.
