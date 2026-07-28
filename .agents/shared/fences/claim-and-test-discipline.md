# Fence: claim and test discipline

Include this fence verbatim in any delegated worker task.

```text
CLAIM AND TEST DISCIPLINE

1. Report four categories separately:
   - observed evidence (with values or file:line);
   - hypotheses;
   - mechanically verified facts (the exact command/artifact and result);
   - user-confirmed runtime behavior.
2. Do not turn `build passed` or `code changed` into `behavior works`.
3. A behavioral success claim requires the user's confirmation in the running
   app. A root-cause claim requires observed evidence and an explicit falsifier.
4. If evidence contradicts the hypothesis, discard or revise it; do not reassert
   it with stronger language.
5. Defer all test work until either the user confirms the behavior works or
   explicitly asks for tests. This is sequencing, not preservation: existing
   tests may be rewritten or deleted after unlock if they encode the wrong
   contract.
6. A plan's test phase, a new feature, a refactor, and "just running tests" do
   not unlock the gate.
```
