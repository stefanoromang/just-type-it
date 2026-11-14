# Automatic cross-app suggestions — 1.6.1

The normal workflow is to type in your own application, wait briefly, click a colored underline, review a correction, and accept it in place. Selecting text and using Rewrite is optional, not required for automatic proofreading.

## Changes

- Ordinary search controls are no longer excluded. Secure/password controls, address/URL bars and recipient controls remain protected.
- Mac resolves an editor through a focused paragraph's ancestors without scanning unrelated text boxes. Chromium rich-text range rectangles can fall back to an identical text child.
- Overlay and badge windows explicitly join other apps' window sets/Spaces. They reset on field changes, refresh if occluded/off-Space, and clamp the badge to the visible display (Word documents can be taller than the screen).
- Menu-bar diagnostics distinguish a watched field from a protected/unsupported field. AI readiness/review activity is visible.
- Mac AI follows the initial rule pass after a 1.2-second pause. Windows gains an automatic local-Ollama proofreading pass for the active paragraph, up to three sentences. Text changes, field switches, disabling or pausing checking cancel pending work. AI remains a reviewable suggestion, not an automatic rewrite.
- Windows AI preserves numeric details/links, rejects large unrelated rewrites and uses a 30-second unavailable-model backoff. No cloud service or new dependency was added.

## Tests

The repeatable Mac live test is `scripts/live-test-everywhere-mac.swift`, with a local HTML fixture in `Tests/browser-writing.html`. It creates and closes only its own browser tab or Word document and restores the clipboard after setup. It does not send messages or submit searches.

```sh
swiftc -parse-as-library Sources/JustTypeIt/FocusedEditor.swift \
  scripts/live-test-everywhere-mac.swift -o "$SCRATCH/jti-everywhere"
"$SCRATCH/jti-everywhere" --chrome plain
"$SCRATCH/jti-everywhere" --chrome search
"$SCRATCH/jti-everywhere" --chrome rich
"$SCRATCH/jti-everywhere" --chrome secret
"$SCRATCH/jti-everywhere" --word
"$SCRATCH/jti-everywhere" --chrome plain --ai
```

Observed successful runs:

| Target | Result |
|---|---|
| Word Mac document | Read focused editor, automatic underline, visible badge, click correction, replace only flagged words: passed |
| Chrome textarea | Same five steps: passed |
| Chrome search field | Same five steps: passed |
| Chrome contenteditable/rich text | Same five steps: passed |
| Chrome password | Excluded: passed |
| AI-only Chrome correction | “She explained me how the system works.” → “She explained to me how the system works.” Automatic underline, click, accept: passed |

Quick corrections appeared in about 0.4–0.6 seconds in sampled runs. The AI-only sample passed in about 1.8–2.6 seconds. One colder repeated run took 9.3 seconds and then lacked the requested word bounds, so that run was not counted as a pass; a repeat passed the full flow. These are measured examples, not timing guarantees; first model load, text size, host accessibility and hardware affect speed.

Windows automated tests exercise the local-AI HTTP proofreading path using a fake local model server. That verifies request/response handling and the suggestion result, not a real Windows model's linguistic quality. Runtime Windows tests cover protected-field classification and Notepad accessibility, replacement and clipboard handling.

## Limits and privacy

- Just Type It must be running. “Launch at Login” is enabled on this Mac, but quitting the app stops suggestions until it is reopened; this release does not install a watchdog or prevent quitting.
- Accessibility permission is required on Mac; AI needs enabled/ready Apple Intelligence. Windows AI requires Ollama and a compatible model already installed.
- Google search is represented by the live local search-control test. The Google site itself, Gmail account, actual Google Docs canvas and every other app were not exhaustively tested. Google Docs needs screen-reader/accessibility support enabled; some custom controls expose neither text nor word positions.
- Password managers and protected fields stay excluded. No covert keylogging or broad clipboard scraping fallback was introduced.
- AI and rules are not infallible. Review suggestions before applying, particularly names, legal/medical text and translations.
