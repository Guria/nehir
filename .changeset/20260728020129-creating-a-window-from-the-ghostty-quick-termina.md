---
"nehir": patch

---

Open the Ghostty quick terminal, create a regular window from it, then dismiss the quick terminal: focus, the layout selection and the command target now stay on the window you just created instead of jumping to a neighbouring one, so a column-width command resizes that new window. Closing a focused window no longer switches away from the current workspace when the quick terminal is involved, and focus-activation traces now record whether an activation was Nehir's own doing.
