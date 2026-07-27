---
"nehir": patch
contributors: [gerardomtz26]
---

Cycling column width no longer recenters the focused column: the viewport keeps its current anchor (including edge snaps) and moves only the minimum needed to keep the resized column visible. Stale relayout frames no longer fight the resize animation, and a window that refuses to shrink now teaches the layout its real minimum width so neighboring columns keep their gap. Fixes #170
