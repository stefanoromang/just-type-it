# Outlook for Mac compatibility

## Fix in 1.1.1

Outlook's native `Editor` group contains a text area in a separate WebKit process,
identified as `ms-outlook-mac-text-editor`. Its app-level focused element and even
focused-window attributes can be absent. The old implementation returned early,
so no live suggestions appeared.

`FocusedEditor` now checks native and system focus, resolves editable ancestors,
and, for Outlook only, searches the active window for the **focused** compose body.
The bounded search detects cycles (Office can expose an element as its own child).
The containing window's process must still match Outlook. It never selects an
unfocused draft, a reading pane, or recipient/search/password fields.

Outlook also returns success for `AXSelectedText` assignment without applying it.
`AccessibilityEdit` therefore selects the exact range, verifies the current draft
and selection, pastes into the active editor, and verifies the complete resulting
text. A no-op or unexpected result is not counted as an accepted correction and
stops Fix all. Clipboard contents are restored only if no other copy took place.

## Tests

Run regression tests without Xcode or an open Outlook window:

```sh
zsh scripts/test-outlook-compatibility.sh
```

These cover cycle-safe traversal, traversal budgets, excluded fields, exact
Unicode-safe replacements with an unchanged signature, and invalid/stale ranges.

### Opt-in live test

This edits **one misspelling in a dedicated test draft**. It never sends mail.

1. Create a new Outlook message with **no recipients**.
2. Set the subject to exactly `Just Type It integration test – no recipients`.
3. At the beginning of the body, type exactly:
   `Their going to the store tomorow. He dont agree.`
4. Keep the insertion point in the body and Outlook frontmost. Run the following
   from a trusted terminal/automation host while keeping that window focused:

   ```sh
   zsh scripts/test-outlook.sh
   ```

The script refuses other subjects, bodies or populated recipient text fields. It
uses the shipping resolver and replacement code, obtains valid word coordinates,
changes only `tomorow` to `tomorrow`, verifies the remaining body/signature and
clipboard, and exits nonzero on failure. Delete only your test draft afterwards.
Normal app testing should additionally check moving/resizing the compose window,
clicking an underline, switching focus to recipients/search, and Fix all.

### Observed on 2026-10-30

- Live test: resolved the WebKit compose body and nonempty word coordinates.
- Live replacement: exact full-body comparison passed; signature unchanged.
- Clipboard restoration: passed.
- Installed app: live underline overlay and suggestion-count badge appeared over
  the Outlook test compose; its summary listed confused-word and agreement fixes.
- No email sent.

These results establish compatibility with the tested desktop compose editor,
not every Outlook version, tenant policy, reply layout or future update.
