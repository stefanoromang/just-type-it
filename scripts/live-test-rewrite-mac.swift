// Created by Stefano Roman Gunness · MIT License
// Live rewrite test in TextEdit: highlight → ✨ button → ⌃⌥R → "More professional" → Replace.
// Requires Accessibility for the terminal. Run: swift scripts/live-test-rewrite-mac.swift
import AppKit

func attr(_ e: AXUIElement, _ k: String) -> CFTypeRef? { var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil }
func str(_ e: AXUIElement, _ k: String) -> String { (attr(e, k) as? String) ?? "" }
func find(_ e: AXUIElement, _ match: (AXUIElement) -> Bool, _ d: Int = 0) -> AXUIElement? {
    if match(e) { return e }
    guard d < 25 else { return nil }
    for c in attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] { if let f = find(c, match, d + 1) { return f } }
    return nil
}
func key(_ k: CGKeyCode, _ f: CGEventFlags = []) { for down in [true, false] { let e = CGEvent(keyboardEventSource: nil, virtualKey: k, keyDown: down)!; e.flags = f; e.post(tap: .cghidEventTap) } }
func jti() -> NSRunningApplication { NSRunningApplication.runningApplications(withBundleIdentifier: "com.stefano.justtypeit").first! }
func jtiWindows() -> [[String: Any]] {
    (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]).filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == jti().processIdentifier }
}

var results: [(String, Bool, String)] = []
let original = "hey so i think maybe we should move the meeting to thursday because alot of people cant make it on tuesday"
NSAppleScript(source: "tell application \"TextEdit\"\nactivate\nmake new document with properties {text:\"\(original)\"}\nend tell")?.executeAndReturnError(nil)
sleep(2)
let te = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first!
te.activate(); usleep(700_000)
let ax = AXUIElementCreateApplication(te.processIdentifier)
guard let w = (attr(ax, kAXWindowsAttribute) as? [AXUIElement])?.first,
      let ta = find(w, { str($0, kAXRoleAttribute) == "AXTextArea" }) else { print("FAIL no TextEdit"); exit(1) }

// 1. Highlight the whole sentence
var all = CFRange(location: 0, length: (str(ta, kAXValueAttribute) as NSString).length)
AXUIElementSetAttributeValue(ta, kAXSelectedTextRangeAttribute as CFString, AXValueCreate(.cfRange, &all)!)
sleep(2)
let button = jtiWindows().contains { ($0[kCGWindowBounds as String] as? [String: CGFloat])?["Width"] == 30 }
results.append(("✨ rewrite button appears next to highlighted text", button, ""))

// 2. ⌃⌥R opens the rewrite panel
key(15, [.maskControl, .maskAlternate])
sleep(2)
let jax = AXUIElementCreateApplication(jti().processIdentifier)
let panel = (attr(jax, kAXWindowsAttribute) as? [AXUIElement] ?? []).first { str($0, kAXTitleAttribute).contains("Rewrite") }
results.append(("⌃⌥R opens the Rewrite panel", panel != nil, ""))
guard let panel else { finish() }
let shows = find(panel, { str($0, kAXValueAttribute).hasPrefix("hey so i think") || str($0, kAXDescriptionAttribute).hasPrefix("hey so i think") }) != nil
results.append(("Panel shows the highlighted text", shows, ""))

// 3. Pick "More professional"
if let pro = find(panel, { str($0, kAXRoleAttribute) == "AXButton" && (str($0, kAXTitleAttribute) + str($0, kAXDescriptionAttribute)).contains("More professional") }) {
    AXUIElementPerformAction(pro, kAXPressAction as CFString)
}
var replaceButton: AXUIElement?
for _ in 0..<30 {
    usleep(500_000)
    replaceButton = find(panel, { str($0, kAXRoleAttribute) == "AXButton" && (str($0, kAXTitleAttribute) + str($0, kAXDescriptionAttribute)) == "Replace" })
    if replaceButton != nil { break }
}
let versionsShown = find(panel, { (str($0, kAXTitleAttribute) + str($0, kAXDescriptionAttribute) + str($0, kAXValueAttribute)).contains("Version 2") }) != nil
results.append(("Professional rewrite produced", replaceButton != nil, ""))
results.append(("Several versions to choose from", versionsShown, ""))

// 4. Replace puts it back in TextEdit
if let replaceButton { AXUIElementPerformAction(replaceButton, kAXPressAction as CFString) }
sleep(3)
let after = str(ta, kAXValueAttribute)
results.append(("Replace puts the rewrite into TextEdit", after != original && !after.isEmpty && after.lowercased().contains("thursday"), after))
results.append(("Original casual text is gone", !after.contains("alot") && !after.hasPrefix("hey so i"), ""))
finish()

func finish() -> Never {
    var fails = 0
    for (n, ok, d) in results { if !ok { fails += 1 }; print(ok ? "PASS" : "FAIL", n, d.isEmpty ? "" : "→ \(d.prefix(160))") }
    NSAppleScript(source: "tell application \"TextEdit\" to close front document saving no")?.executeAndReturnError(nil)
    print(fails == 0 ? "REWRITE LIVE: ALL PASS" : "REWRITE LIVE: \(fails) FAILED")
    exit(fails == 0 ? 0 : 1)
}
