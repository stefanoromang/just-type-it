#!/bin/zsh
# Created by Stefano Roman Gunness · MIT License
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d "${TMPDIR:-/tmp}/jti-outlook-regression.XXXXXX")
trap 'rm -f "$OUT/tests"; rmdir "$OUT"' EXIT
swiftc -parse-as-library Sources/JustTypeIt/FocusedEditor.swift \
  Sources/JustTypeIt/AccessibilityEdit.swift Tests/JustTypeItTests/OutlookCompatibilityTests.swift -o "$OUT/tests"
"$OUT/tests"
