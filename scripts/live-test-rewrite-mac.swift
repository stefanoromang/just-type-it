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
let translation = CommandLine.arguments.contains("--spanish") || CommandLine.arguments.contains("--english")
let original = CommandLine.arguments.contains("--english")
    ? "Por favor, envía el pedido A729 de 24 cajas antes del viernes."
    : translation ? "Please send order A729 for 24 boxes by Friday."
    : "Hey, I think maybe we should move the meeting to Thursday because many people cannot make it on Tuesday."
let action = CommandLine.arguments.contains("--spanish") ? "Translate to Spanish" : CommandLine.arguments.contains("--english") ? "Translate to English" : "More professional"
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

guard NSWorkspace.shared.frontmostApplication?.processIdentifier == te.processIdentifier else { print("INCONCLUSIVE: TextEdit lost focus before the shortcut."); exit(2) }
// 2. ⌃⌥R opens the rewrite panel
key(15, [.maskControl, .maskAlternate])
sleep(2)
let jax = AXUIElementCreateApplication(jti().processIdentifier)
let panel = (attr(jax, kAXWindowsAttribute) as? [AXUIElement] ?? []).first { str($0, kAXTitleAttribute).contains("Rewrite") }
if panel == nil && NSWorkspace.shared.frontmostApplication?.processIdentifier != te.processIdentifier {
    print("INCONCLUSIVE: another app took focus while opening Rewrite."); exit(2)
}
results.append(("⌃⌥R opens the Rewrite panel", panel != nil, ""))
guard let panel else { finish() }
let shows = find(panel, { str($0, kAXValueAttribute).hasPrefix(String(original.prefix(15))) || str($0, kAXDescriptionAttribute).hasPrefix(String(original.prefix(15))) }) != nil
results.append(("Panel shows the highlighted text", shows, ""))

// 3. Pick "More professional"
if let pro = find(panel, { str($0, kAXRoleAttribute) == "AXButton" && (str($0, kAXTitleAttribute) + str($0, kAXDescriptionAttribute)).contains(action) }) {
    AXUIElementPerformAction(pro, kAXPressAction as CFString)
}
var replaceButton: AXUIElement?
for _ in 0..<30 {
    usleep(500_000)
    replaceButton = find(panel, { str($0, kAXRoleAttribute) == "AXButton" && (str($0, kAXTitleAttribute) + str($0, kAXDescriptionAttribute)) == "Replace" })
    if replaceButton != nil { break }
}
let versionsShown = find(panel, { (str($0, kAXTitleAttribute) + str($0, kAXDescriptionAttribute)) == "Try again" }) != nil
results.append(("\(action) result produced", replaceButton != nil, ""))
let customize = find(panel, { (str($0, kAXTitleAttribute) + str($0, kAXDescriptionAttribute)) == "Customize…" }) != nil
results.append(("Quick Actions customization available", customize, ""))
results.append(("Another version available on demand", versionsShown, ""))

// 4. Replace puts it back in TextEdit
if let replaceButton {
    jti().activate(); usleep(200_000)
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == jti().processIdentifier else { print("INCONCLUSIVE: Rewrite lost focus before Replace."); exit(2) }
    AXUIElementPerformAction(replaceButton, kAXPressAction as CFString)
}
sleep(3)
let after = str(ta, kAXValueAttribute)
results.append(("Replace puts the result into TextEdit", after != original && !after.isEmpty && (translation ? after.contains("A729") && after.contains("24") : after.lowercased().contains("thursday")), after))
results.append(("Original selection is replaced", after != original && !after.hasPrefix("Hey, I think maybe"), ""))
finish()

func finish() -> Never {
    var fails = 0
    for (n, ok, d) in results { if !ok { fails += 1 }; print(ok ? "PASS" : "FAIL", n, d.isEmpty ? "" : "→ \(d.prefix(160))") }
    NSAppleScript(source: "tell application \"TextEdit\" to close front document saving no")?.executeAndReturnError(nil)
    print(fails == 0 ? "REWRITE LIVE: ALL PASS" : "REWRITE LIVE: \(fails) FAILED")
    exit(fails == 0 ? 0 : 1)
}
