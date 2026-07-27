---
"nehir": patch
contributors: [gerardomtz26]
---

Cycling column width no longer recenters the focused column: the viewport keeps its current anchor (including edge snaps) and moves only the minimum needed to keep the resized column visible. A centered lone window is the intentional exception — it now stays centered as its width changes instead of staying pinned at its old x-position and clamping against the display edge. Stale relayout frames no longer fight the resize animation, and a window that refuses to shrink now teaches the layout its real minimum width so neighboring columns keep their gap. Fixes #170
