---
"nehir": patch
contributors: [dagrlx]
---

Switching, creating, and closing Ghostty tabs no longer destroys and re-creates the window's layout column: window identity is preserved across the tab's window-id swap, so column position and width survive. Rapid tab bursts can still show brief transient windows, but the layout now settles back on its own instead of accumulating phantom windows and empty space that only a restart could clear. Fixes #191.
