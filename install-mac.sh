#!/bin/zsh
# Just Type It – installer for macOS
# Created by Stefano Roman Gunness · MIT License
#
# Builds Just Type It from source on this Mac and installs it to ~/Applications.
# No admin password needed.
#
# One-line install:
#   curl -fsSL https://raw.githubusercontent.com/stefanoromang/just-type-it/main/install-mac.sh | zsh

set -e
REPO_URL="https://github.com/stefanoromang/just-type-it.git"

bold() { print -P "%B$1%b"; }
fail() { print -P "%F{red}✗ $1%f"; exit 1; }
ok()   { print -P "%F{green}✓%f $1"; }

bold "Just Type It – free, private AI writing assistant for Mac"
echo "Created by Stefano Roman Gunness"
echo

# 1. Requirements
[[ "$(uname)" == "Darwin" ]] || fail "This installer is for macOS. On Windows, run install-windows.cmd or download JustTypeIt-Setup.exe from https://github.com/stefanoromang/just-type-it/releases/latest"
[[ "$(uname -m)" == "arm64" ]] || fail "Just Type It needs a Mac with Apple silicon (M1 or newer)."
MACOS_MAJOR=$(sw_vers -productVersion | cut -d. -f1)
(( MACOS_MAJOR >= 26 )) || fail "Just Type It needs macOS 26 (Tahoe) or newer. You have $(sw_vers -productVersion)."
ok "macOS $(sw_vers -productVersion) on Apple silicon"

if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Apple's free Command Line Tools are needed to build the app."
  echo "A window will open – click Install, wait for it to finish, then run this installer again."
  xcode-select --install 2>/dev/null || true
  exit 1
fi
ok "Command Line Tools found"

# 2. Get the source (use this folder if we're already inside it)
SCRIPT_DIR="${0:A:h}"
if [[ -f "$SCRIPT_DIR/Package.swift" && -d "$SCRIPT_DIR/Sources/JustTypeIt" ]]; then
  SRC="$SCRIPT_DIR"
else
  SRC="${TMPDIR:-/tmp}/just-type-it-src"
  rm -rf "$SRC"
  echo "Downloading the source…"
  git clone --depth 1 "$REPO_URL" "$SRC" >/dev/null 2>&1 || fail "Could not download the source from $REPO_URL"
fi
ok "Source ready"

# 3. Build and install
echo "Building (this takes about a minute the first time)…"
cd "$SRC"
./build-app.sh >/dev/null 2>"${TMPDIR:-/tmp}/just-type-it-build.log" || {
  tail -20 "${TMPDIR:-/tmp}/just-type-it-build.log"
  fail "Build failed. Full log: ${TMPDIR:-/tmp}/just-type-it-build.log"
}
ok "Installed to ~/Applications/Just Type It.app"

# 4. Launch
open "$HOME/Applications/Just Type It.app"
echo
bold "Done!"
echo "Start typing in Just Type It, or select text in any app and press Control-Option-G."
echo "Turn on Apple Intelligence (System Settings › Apple Intelligence & Siri) for AI rewrites, tone changes and agents."
