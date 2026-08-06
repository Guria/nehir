# Fence: claim and test discipline

Include this fence verbatim in any delegated worker task.

```text
CLAIM AND TEST DISCIPLINE

1. Report five categories separately:
   - observed evidence (with values or file:line);
   - user testimony (user said it; no artifact corroborates it — label it, do
     not use it as causal evidence);
   - hypotheses;
   - mechanically verified facts (the exact command/artifact and result);
   - user-confirmed runtime behavior.
2. Do not turn `build passed` or `code changed` into `behavior works`.
3. A behavioral success claim requires the user's confirmation in the running
   app. A root-cause claim requires observed evidence and an explicit falsifier.
4. Before using a trace event as proof that a code path ran, bind the event's
   exact event=/context=/source=/phase=/reason= string to its source emitter
   (file:line). Do not attribute an event to a path that does not emit it.
5. Name the exact mechanical signal. Engine-computed or scheduled state is not
   on-screen effect (target advanced ≠ revealed; scheduled ≠ fired; requested ≠
   executed).
6. If evidence contradicts the hypothesis — including a signal that would have
   been suppressed if the hypothesis were true — discard or revise it; do not
   reassert it with stronger language.
7. Do not invent reproduction steps from a hypothesis. Steps must fit the
   observed timeline and topology; if none exist, say so.
8. Defer all test work until either the user confirms the behavior works or
   explicitly asks for tests. This is sequencing, not preservation: existing
   tests may be rewritten or deleted after unlock if they encode the wrong
   contract.
9. A plan's test phase, a new feature, a refactor, and "just running tests" do
   not unlock the gate.
```
