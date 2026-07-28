---
"nehir": patch

---

Moving a window or column to another workspace now honors the "Follow Window to Workspace" setting on every move: window up/down, column up/down, and column-to-numbered-workspace previously always left focus behind. The source monitor's scroll animation now settles on every move path instead of continuing to spring through the transition, and a move no longer steals focus back if you switch workspaces before the layout finishes.
