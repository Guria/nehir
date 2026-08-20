---
"nehir": patch

---

Fix a window moved to another workspace sometimes staying off screen. When the destination workspace needed to scroll to bring the moved window into view, the scroll was worked out but never started, so the window stayed parked off the edge of the screen while still receiving keyboard input.
