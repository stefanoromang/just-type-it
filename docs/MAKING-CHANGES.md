# Making changes to Just Type It

This folder contains everything needed to change, build, test and publish Just Type It for Mac and Windows. It's a Git repository connected to https://github.com/stefanoromang/just-type-it.

## What's in the folder

| Folder / file | What it is |
|---|---|
| `Sources/JustTypeIt/` | The Mac app (Swift / SwiftUI) |
| `windows/JustTypeIt/` | The Windows app (C# / .NET 10) |
| `windows/JustTypeIt.Core/` | The Windows checking engine and `rules.json` (grammar rules shared with the Mac app) |
| `windows/JustTypeIt.Tests/` | Windows engine tests |
| `windows/installer/` | Windows installer script (Inno Setup) |
| `Tests/` | Shared test sentences (64 errors, clean writing) |
| `scripts/` | Icon, signing and test scripts |
| `build-app.sh` | Builds and installs the Mac app to `~/Applications` |
| `install-mac.sh`, `install-windows.ps1` | The one-line installers people use |
| `.github/workflows/` | Automatic Mac and Windows builds, tests and Windows installer on GitHub |

## Change and install the Mac app

```bash
cd ~/Documents/"Stefano Roman Gunness - Just Type It"
./build-app.sh                       # builds, signs and installs ~/Applications/Just Type It.app
open ~/Applications/"Just Type It.app"
```

Needs Apple's Command Line Tools (`xcode-select --install`). Xcode isn't required.

## Test

```bash
swift build -c release
.build/release/JustTypeIt --self-test --errors Tests/error-corpus.txt --corpus Tests/clean-corpus.txt
.build/release/JustTypeIt --self-test --rewrite      # all 17 rewrite styles (Apple Intelligence)
zsh scripts/test-outlook-compatibility.sh
swift scripts/live-test-mac.swift                    # types into TextEdit: autocorrect, underlines, badge
swift scripts/live-test-rewrite-mac.swift            # highlight → ⌃⌥R → rewrite → Replace
cd windows && ~/.dotnet/dotnet test JustTypeIt.Tests/JustTypeIt.Tests.csproj
```

The live tests need Accessibility permission for the terminal running them.

## If you change grammar rules

Grammar rules are written in the Mac sources (`RuleData.swift`, `GrammarRules.swift`, `StyleData.swift`). After changing them, refresh the copy used by Windows:

```bash
.build/release/JustTypeIt --self-test --export-rules windows/JustTypeIt.Core/rules.json
```

The Mac build on GitHub fails if you forget, so the two apps never drift apart.

## Publish a new version

1. Raise the version in `build-app.sh` (`CFBundleShortVersionString`, `CFBundleVersion`), `windows/JustTypeIt/JustTypeIt.csproj` (`<Version>`) and `windows/installer/JustTypeIt.iss` (`AppVersion`).
2. Commit and push:
   ```bash
   git add -A && git commit -m "Describe the change" && git push
   ```
   GitHub builds and tests both apps (including a live test on a real Windows machine).
3. Create a release, for example: `gh release create v1.4 --title "Just Type It 1.4" --notes "What changed"`. GitHub attaches the Windows installer and portable zip automatically. The Mac install command always builds the latest code.

## Generated files (safe to delete)

`.build/`, `build/`, `windows/*/bin/`, `windows/*/obj/` and `windows/dist/` are created by builds and recreated automatically. They're ignored by Git.
