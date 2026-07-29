---
"nehir": patch
contributors: [dagrlx]
---

Renaming a file from Finder's context menu works again while Nehir is running: application child surfaces that are not real windows (such as Finder's inline rename editor) are no longer admitted as managed windows, so managed focus recovery no longer dismisses them. Fixes #179.
