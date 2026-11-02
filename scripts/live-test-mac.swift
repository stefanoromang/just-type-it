// Created by Stefano Roman Gunness · MIT License
// Live test: types into a new TextEdit document (requires Accessibility for the terminal) and checks
// autocorrect, underlines, the suggestion badge, tone emoji and the green check. Run: swift scripts/live-test-mac.swift
import AppKit

func attr(_ e: AXUIElement, _ k: String) -> CFTypeRef? { var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil }
func textArea(_ e: AXUIElement, _ d: Int = 0) -> AXUIElement? {
    if attr(e, kAXRoleAttribute) as? String == "AXTextArea" { return e }
    guard d < 12 else { return nil }
    for c in attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] { if let f = textArea(c, d + 1) { return f } }
    return nil
}
func type(_ s: String) {
    for ch in s {
        var u = Array(String(ch).utf16)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)!
            e.keyboardSetUnicodeString(stringLength: u.count, unicodeString: &u)
            e.post(tap: .cghidEventTap)
        }
        usleep(45_000)
    }
}
func jtiWindows() -> [(layer: Int, rect: CGRect)] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
    return list.filter { ($0[kCGWindowOwnerName as String] as? String)?.contains("Just Type") == true }.map {
        let b = $0[kCGWindowBounds as String] as! [String: CGFloat]
        return ($0[kCGWindowLayer as String] as! Int, CGRect(x: b["X"]!, y: b["Y"]!, width: b["Width"]!, height: b["Height"]!))
    }
}

let script = "tell application \"TextEdit\"\nactivate\nmake new document\nend tell"
NSAppleScript(source: script)?.executeAndReturnError(nil)
sleep(2)
let te = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first!
te.activate(options: [.activateAllWindows])
usleep(800_000)
guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.TextEdit" else { print("FAIL TextEdit is not frontmost (\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"))"); exit(2) }
let ax = AXUIElementCreateApplication(te.processIdentifier)
guard let w = (attr(ax, kAXWindowsAttribute) as? [AXUIElement])?.first, let ta = textArea(w) else { print("FAIL no TextEdit text area"); exit(1) }

var results: [(String, Bool, String)] = []
// 1. Autocorrect while typing
type("I think teh report is ready and we dont need more time. ")
usleep(1_500_000)
let afterTyping = attr(ta, kAXValueAttribute) as? String ?? ""
results.append(("Autocorrect teh → the", afterTyping.contains("think the report"), afterTyping))
results.append(("Autocorrect dont → don't", afterTyping.contains("we don't need"), afterTyping))

// 2. Underlines + badge for a real mistake
type("Me and him was late to the meeting yesterday.")
sleep(3)
let wins = jtiWindows()
results.append(("Underline overlay shown", wins.contains { $0.layer == 3 }, "\(wins)"))
results.append(("Suggestion badge shown", wins.contains { $0.layer == 101 && $0.rect.height == 26 }, ""))
let badgeWide = wins.contains { $0.layer == 101 && $0.rect.height == 26 && $0.rect.width > 40 }
results.append(("Tone emoji next to badge", badgeWide, ""))

// 3. Clean text: green check badge
let all = CFRange(location: 0, length: (attr(ta, kAXValueAttribute) as? String ?? "").utf16.count)
var r = all
AXUIElementSetAttributeValue(ta, kAXSelectedTextRangeAttribute as CFString, AXValueCreate(.cfRange, &r)!)
AXUIElementSetAttributeValue(ta, kAXSelectedTextAttribute as CFString, "Thanks for the update. I will send the report on Friday." as CFString)
sleep(3)
let clean = jtiWindows()
results.append(("Clean text: no underlines", !clean.contains { $0.layer == 3 }, ""))
results.append(("Clean text: green check badge", clean.contains { $0.layer == 101 && $0.rect.height == 26 }, ""))

var fails = 0
for (n, ok, d) in results { if !ok { fails += 1 }; print(ok ? "PASS" : "FAIL", n, ok ? "" : d) }
NSAppleScript(source: "tell application \"TextEdit\" to close front document saving no")?.executeAndReturnError(nil)
print(fails == 0 ? "LIVE: ALL PASS" : "LIVE: \(fails) FAILED")
exit(fails == 0 ? 0 : 1)
