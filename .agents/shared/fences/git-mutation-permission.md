# Fence: git mutation permission

Include this fence verbatim in any delegated worker task.

```text
GIT MUTATION PERMISSION

1. Do not mutate git without explicit permission for that exact action. This
   includes stage/add, commit, push, amend, restore, reset, revert, stash,
   rebase, merge, cherry-pick, branch creation/switch/deletion, tags, and git rm.
2. Permission does not chain: commit does not authorize stage, push, amend, or
   another commit.
3. Never alter changes or staging created by the user, even to clean up or undo
   something you believe was mistaken.
4. If an unauthorized mutation happens, report it and stop. Do not auto-undo it.
5. Before asking permission, state the exact action, affected files/refs, and
   impact on the working tree/index.
6. Read-only git commands are allowed.
```
