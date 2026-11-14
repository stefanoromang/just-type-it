// Created by Stefano Roman Gunness · MIT License
// Real cross-app check: read focused text → underline → suggestion card → verified replacement.
// swiftc -parse-as-library Sources/JustTypeIt/FocusedEditor.swift scripts/live-test-everywhere-mac.swift -o <scratch>/jti-everywhere
// Run --chrome plain|search|rich|secret, or --word. Uses only a new local test tab/document.
import AppKit

@main @MainActor
struct EverywhereLiveTest {
    static func apple(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { print("SETUP:", error) }
        return result
    }
    static func wait(_ seconds: Double, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }
    static func find(_ el: AXUIElement, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
        FocusedEditor.search(roots: [el], maxNodes: 500, maxDepth: 20, children: {
            FocusedEditor.attribute($0, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }, matches: match)
    }
    static func main() { exit(run()) }
    static func run() -> Int32 {
        guard AXIsProcessTrusted() else { print("BLOCKED: Accessibility permission required"); return 2 }
        let word = CommandLine.arguments.contains("--word")
        let ai = CommandLine.arguments.contains("--ai")
        let field = CommandLine.arguments.firstIndex(of: "--chrome").flatMap { index in CommandLine.arguments.indices.contains(index + 1) ? CommandLine.arguments[index + 1] : nil } ?? "plain"
        let bundle = word ? "com.microsoft.Word" : "com.google.Chrome"
        var document = ""
        var tabID = 0
        let original = ai ? "She explained me how the system works." : "Before. Their going to the store tomorrow. After."
        let expected = ai ? "She explained to me how the system works." : "Before. They're going to the store tomorrow. After."
        if word {
            document = apple("tell application \"Microsoft Word\"\nactivate\nset d to make new document\nset content of text object of d to \"\(original)\"\nselect text object of d\nreturn name of d\nend tell")?.stringValue ?? ""
        } else {
            let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/browser-writing.html").absoluteString + "#" + field
            tabID = Int(apple("tell application \"Google Chrome\"\nactivate\nif (count of windows) = 0 then make new window\nset t to make new tab at end of tabs of front window with properties {URL:\"\(url)\"}\nset active tab index of front window to count of tabs of front window\nreturn id of t\nend tell")?.int32Value ?? 0)
        }
        defer {
            if word && !document.isEmpty {
                _ = apple("tell application \"Microsoft Word\" to close document \"\(document)\" saving no")
            } else if tabID != 0 {
                _ = apple("tell application \"Google Chrome\"\nrepeat with w in windows\nrepeat with t in tabs of w\nif id of t is \(tabID) then\nclose t\nreturn\nend if\nend repeat\nend repeat\nend tell")
            }
        }
        _ = wait(5) { NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first != nil }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first,
              let jti = NSRunningApplication.runningApplications(withBundleIdentifier: "com.stefano.justtypeit").first else {
            print("BLOCKED: target app or Just Type It is not running"); return 2
        }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(ax, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        app.activate()
        _ = wait(3) { NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier }
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        if word, let page = find(ax, { FocusedEditor.string($0, kAXRoleAttribute) == "AXLayoutArea" }) {
            var origin = CGPoint.zero
            if let p = FocusedEditor.attribute(page, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(), AXValueGetValue(p as! AXValue, .cgPoint, &origin) {
                let point = CGPoint(x: origin.x + 130, y: origin.y + 100)
                for type in [CGEventType.leftMouseDown, .leftMouseUp] { CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap) }
            }
        }
        var editor: AXUIElement?
        _ = wait(5) { editor = FocusedEditor.resolve(app: ax, pid: app.processIdentifier, bundleID: bundle); return editor != nil }
        if field == "secret" {
            print(editor == nil ? "PASS protected password field is excluded" : "FAIL password field was accepted")
            return editor == nil ? 0 : 1
        }
        guard let editor else {
            print("FAIL focused editor could not be resolved; front=", NSWorkspace.shared.frontmostApplication?.localizedName ?? "")
            if let focus = FocusedEditor.element(ax, kAXFocusedUIElementAttribute) {
                print("DIAGNOSTIC focus", FocusedEditor.string(focus, kAXRoleAttribute) ?? "", FocusedEditor.string(focus, kAXDescriptionAttribute) ?? "")
            }
            return 1
        }
        if !word && FocusedEditor.string(editor, kAXValueAttribute)?.contains(original) != true {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { print("INCONCLUSIVE: browser lost focus"); return 2 }
            AXUIElementSetAttributeValue(editor, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            if let pos = FocusedEditor.attribute(editor, kAXPositionAttribute), let size = FocusedEditor.attribute(editor, kAXSizeAttribute) {
                var p = CGPoint.zero; var s = CGSize.zero
                if CFGetTypeID(pos) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID(),
                   AXValueGetValue(pos as! AXValue, .cgPoint, &p), AXValueGetValue(size as! AXValue, .cgSize, &s) {
                    let point = CGPoint(x: p.x + min(40, s.width / 2), y: p.y + min(25, s.height / 2))
                    for type in [CGEventType.leftMouseDown, .leftMouseUp] { CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap) }
                    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                }
            }
            // Paste through the real editor; AXValue is not a reliable contenteditable setter.
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
                  let active = FocusedEditor.resolve(app: ax, pid: app.processIdentifier, bundleID: bundle), CFEqual(active, editor) else {
                print("INCONCLUSIVE: focused field changed before setup paste"); return 2
            }
            let pb = NSPasteboard.general
            let saved = (pb.pasteboardItems ?? []).map { item in Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }) }
            pb.clearContents(); pb.setString(original, forType: .string)
            let owned = pb.changeCount
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: down)
                event?.flags = .maskCommand; event?.post(tap: .cghidEventTap)
            }
            _ = wait(2) { FocusedEditor.string(editor, kAXValueAttribute)?.contains(original) == true }
            if pb.changeCount == owned {
                pb.clearContents()
                pb.writeObjects(saved.map { data in let item = NSPasteboardItem(); for (type, bytes) in data { item.setData(bytes, forType: type) }; return item })
            }
        }
        guard wait(2, { FocusedEditor.string(editor, kAXValueAttribute)?.contains(original) == true }) else {
            print("FAIL target text was not readable; length=", FocusedEditor.string(editor, kAXValueAttribute)?.utf16.count ?? -1); return 1
        }
        var failures = 0
        func record(_ name: String, _ ok: Bool) { print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1 } }
        record("Focused \(word ? "Word" : "Chrome \(field)") editor is readable", true)
        let jax = AXUIElementCreateApplication(jti.processIdentifier)
        func windows() -> [[String: Any]] {
            (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []).filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == jti.processIdentifier }
        }
        func hasOverlay() -> Bool { windows().contains { ($0[kCGWindowLayer as String] as? Int) == 3 } }
        let start = Date()
        let underline = wait(ai ? 15 : 5) { hasOverlay() && windows().contains { ($0[kCGWindowLayer as String] as? Int) == 101 } }
        if !underline { print("DIAGNOSTIC visible windows", windows().map { [$0[kCGWindowLayer as String], $0[kCGWindowBounds as String]] }) }
        record("Automatic grammar underline (\(String(format: "%.2f", Date().timeIntervalSince(start))) s)", underline)
        record("Suggestion badge", windows().contains { ($0[kCGWindowLayer as String] as? Int) == 101 })
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { print("INCONCLUSIVE: target lost focus before click"); return 2 }
        let text = FocusedEditor.string(editor, kAXValueAttribute) ?? ""
        let range = (text as NSString).range(of: ai ? "explained" : "Their going")
        var wordBounds: CGRect?
        _ = wait(2) { wordBounds = FocusedEditor.bounds(editor, range: range); return wordBounds != nil }
        guard let rect = wordBounds else { print("FAIL word bounds unavailable"); return 1 }
        let point = CGPoint(x: rect.midX, y: rect.maxY - 1)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] { CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap) }
        var fix: AXUIElement?
        _ = wait(4) {
            fix = find(jax) {
                let label = (FocusedEditor.string($0, kAXTitleAttribute) ?? "") + (FocusedEditor.string($0, kAXDescriptionAttribute) ?? "")
                return FocusedEditor.string($0, kAXRoleAttribute) == "AXButton" && label.contains(ai ? "explained to" : "They're going")
            }
            return fix != nil
        }
        record("Click underline opens correction suggestion", fix != nil)
        if let fix { AXUIElementPerformAction(fix, kAXPressAction as CFString) }
        let applied = wait(4) { FocusedEditor.string(editor, kAXValueAttribute)?.contains(expected) == true }
        if !applied { print("DIAGNOSTIC result", FocusedEditor.string(editor, kAXValueAttribute) ?? "<missing>") }
        record("Accept changes only the flagged text", applied)
        print(failures == 0 ? "EVERYWHERE: ALL PASS" : "EVERYWHERE: \(failures) FAILED")
        return failures == 0 ? 0 : 1
    }
}
