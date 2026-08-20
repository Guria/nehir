---
"nehir": patch

---

Fix a moved window being hidden behind other windows on its destination workspace. When you moved a window to another workspace and Nehir followed it there, the windows already on that workspace were raised to the front while the moved window was not, so it held keyboard focus but was covered by whatever else was there. The focused window is now raised along with them.
