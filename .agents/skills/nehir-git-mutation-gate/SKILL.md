---
name: nehir-git-mutation-gate
description: BEFORE any git mutation—stage/add, commit, push, amend, reset, restore, revert, stash, rebase, merge, branch creation/switch/deletion, tag, or git rm. Each mutation requires explicit user permission for that exact action; one permission never implies the next.
---

# Git-mutation gate: no git writes without per-action permission

Git mutations that the user did not authorize for that exact step can destroy
in-flight work, especially when they alter changes or staging created by the
user. Autonomy covers reading, reasoning, and requested file edits; it never
covers publishing or rewriting git state.

## This gate covers

- `git add`, `git stage`, `git rm`
- `git commit`, `git commit --amend`
- `git push`, including tags
- `git reset`, `git restore`, `git revert`
- `git stash`
- `git rebase`, `git merge`, cherry-pick
- branch creation, switching, renaming, or deletion
- tags
- force operations of any kind
- any non-git command that mutates the index, refs, or tracked files as a git
  operation

Read-only commands such as `git status`, `git diff`, `git log`, and
`git show` do not require permission.

## Rules

1. **Permission is per action.** `Commit this` authorizes one commit—not staging,
   pushing, amending, or another commit unless those actions were also explicit.
2. **Permission does not carry across threads or contexts.**
3. **The user's staging is inviolable.** Do not stage, unstage, restore, revert,
   reorder, or otherwise alter changes the user staged themselves.
4. **Do not auto-undo an unauthorized action.** Undoing it is another mutation.
   Report exactly what happened and wait for instructions.
5. **Stay inside the named scope.** If permission names specific files, do not
   include others.
6. **No implicit branch exception.** Being on the default branch does not grant
   permission to create or switch branches. Ask first.

## Before requesting permission

State:

- the exact command or action you propose;
- why it is needed;
- the files, refs, or ranges it will affect;
- whether it would touch the user's working tree or index.

Then stop and wait for an explicit answer.

## Red flags

- "I went ahead and committed because it was ready."
- `git add -A` or `git add .` when only specific files were requested.
- Restoring or reverting something because you decided it was a mistake.
- Any `--force`, `--hard`, or `--amend` without explicit per-use permission.
