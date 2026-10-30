#!/bin/zsh
# Created by Stefano Roman Gunness · MIT License
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d "${TMPDIR:-/tmp}/jti-outlook-test.XXXXXX")
trap 'rm -f "$OUT/outlook-smoke"; rmdir "$OUT"' EXIT
swiftc -parse-as-library Sources/JustTypeIt/FocusedEditor.swift \
  Sources/JustTypeIt/AccessibilityEdit.swift scripts/outlook-smoke.swift -o "$OUT/outlook-smoke"
"$OUT/outlook-smoke"
