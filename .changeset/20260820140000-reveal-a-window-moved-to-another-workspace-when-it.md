---
"nehir": patch

---

Fix a window moved to another workspace staying off screen. When the moved window already had focus, Nehir treated the follow-up focus notification as the same window being re-focused in place and kept the destination workspace's viewport where it was, leaving the moved window parked off the edge of the screen while still receiving keyboard input. A window re-focused after changing workspace is now scrolled into view.
