# Just Type It 1.6 review

Reviewed for one person editing emails and documents on a Mac or Windows PC. Two rounds, ten checks per round. A passing test is evidence for that case, not a guarantee of perfect English, Spanish, or AI output.

## Round 1 — baseline and connected-code review

| # | Check | Result / action |
|---|---|---|
| 1 | Mac release build | Passed. Two installed Command Line Tools linker search paths are absent; linking succeeds. |
| 2 | Windows engine and app build | Baseline 61 tests passed. Removed duplicate manifest DPI configuration; app now builds without warnings. |
| 3 | English error recall | 64/64 original and 46/46 hard examples caught. |
| 4 | Correct English | Existing clean corpora passed. Found incorrect “good on” replacement during manual result inspection; narrowed it and added explicit “did well on the exam” coverage. |
| 5 | Spanish grammar and clean writing | 38/38 errors caught. Removed the false “asiendo → haciendo” rule and the invalid “hay lo que → ahí lo que” replacement. |
| 6 | Multilingual routing | Found Windows still checked foreign paragraphs with the English dictionary before discarding the results; it now checks only in the chosen paragraph language. Mac AI language is selected per sentence. |
| 7 | Rewrites and translation | Translation was absent and blocked by the shared “keep original language” instruction. Added explicit translation modes without that conflict. |
| 8 | Cross-app replacement | Found paths that pasted even when the source range could not be verified. Now retain source snapshots / ranges and copy the result instead of blind pasting. |
| 9 | Settings and saved work | Added seven-slot preference migration / round-trip tests; preserved drafts if Windows preference decoding fails; blocked Mac document overwrites if backup creation fails. |
| 10 | Responsiveness / UI | Repeated 2,800-word checks measured 204 ms before and 23 ms after length/detection caching fixes; edit checks 197 ms → 28 ms in the same initial comparison. Changed rewrite UI from waiting for three versions to one first result and on-demand alternatives. |

## New feature — seven configurable Quick Actions

Defaults: **Professional, Enthusiastic, Casual, Shorter, Fix Grammar, Translate to Spanish, Translate to English**. Each slot can be changed from the rewrite panel. Existing modes remain available. The main editor also exposes the same actions.

Translation uses Apple Intelligence on Mac or a local Ollama model on Windows. No cloud account or new dependency was added. Source text is treated as data. Results are previews requiring acceptance. Numeric details, links, and email addresses must remain unchanged or the translation is rejected. That safeguard can conservatively reject a legitimate translation that reformats a number/date.

Competitor reference: [Grammarly selected-text translation](https://support.grammarly.com/hc/en-us/articles/27518589299725-Introducing-Grammarly-s-translation-feature) and [paragraph-level rewrites](https://support.grammarly.com/hc/en-us/articles/30916398193037-Introducing-paragraph-level-rewrites). These confirm a comparable workflow exists. We did not run a head-to-head quality or latency benchmark. No claim of overall superiority is made.

## Round 2 — regression and final review

| # | Check | Evidence |
|---|---|---|
| 1 | Mac final build / installed app | Release build and local signed installation; version 1.6. |
| 2 | Windows final engine/build | 74 tests, including local fake-Ollama HTTP round-trips in both translation directions; release build. These test the transport/prompt, not actual Windows model quality. |
| 3 | English errors / corrected meaning | Original and hard corpora re-run; explicit expected replacement test for “did good on the exam → did well”. |
| 4 | False alarms | Expanded clean English and Spanish corpora re-run. Windows tests now require zero missed corpus examples and zero clean-writing correctness flags, rather than allowing several. |
| 5 | Both real translation directions | Apple Intelligence produced four correct-language sample translations in about 0.57–0.78 s, retaining 1250 euros, A729, 24, 12/11/2026 and the URL. Human linguistic review of arbitrary translations remains necessary. |
| 6 | Translation guardrails | Changed amounts and email addresses rejected; unchanged order numbers / links accepted; empty, oversized, cancelled requests tested. |
| 7 | Preference/configuration | Seven defaults, configurable values, unknown/short preference migration, persistence round-trip and native labelled pickers checked. Windows live UI not visually inspected. |
| 8 | Safe edits / clipboard | Emoji and stale-range cases tested, source selection mismatch tests added to Windows runtime self-test, cancellation and foreground rechecks reviewed. Clipboard restoration does not overwrite a newer paste-time clipboard change. |
| 9 | Live typing / selected rewrite | Mac TextEdit typing test passed 7/7 after keyboard-idle protection fixed a real autocorrect race. Selected-text rewrite UI generated a result and exposed customization / retry, but uninterrupted full replacement/translation runs remain inconclusive because other desktop apps repeatedly take focus. Do not interpret those runs as passing. |
| 10 | Final performance / packaging / diff | Benchmarks re-run (timings vary under desktop load), Outlook compatibility 5/5, shared rule export synchronized, version numbers aligned, `git diff --check` clean. |

## Remaining limits

- Live checking waits for a brief typing pause; system accessibility polling and the host app add latency. It is not literally instantaneous.
- Background autocorrect now waits at least 600 ms of real input idle and rechecks text/focus; it cannot make every third-party editor's input processing atomic.
- No full Gmail, Word, Outlook, Excel, browser, or Windows desktop visual matrix was run in this review. Existing Outlook compatibility tests are regression fixtures, not a fresh Outlook compose session.
- Windows translation requires an installed working Ollama model; Windows non-English spelling needs the corresponding language pack. The test runner may not have Spanish installed.
- Some macOS dictionary results and grammar rules are version-dependent. AI can still produce incorrect wording or change meaning. Review high-stakes writing and translations.
- Seven action buttons are configured and persisted, but there is no cloud synchronization or account system.
