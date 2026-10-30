// Created by Stefano Roman Gunness · MIT License
// Run with scripts/test-outlook.sh while a recipient-free test compose is focused in Outlook.
// Only the exact subject and test sentence below authorize a replacement. Never sends mail.
import AppKit
import ApplicationServices

@main
struct OutlookSmokeTest {
    @MainActor static func main() {
        let done = DispatchSemaphore(value: 0)
        Task { @MainActor in await run(); done.signal() }
        while done.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    @MainActor static func run() async {
        let marker = "Just Type It integration test – no recipients"
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == FocusedEditor.outlookID else {
            print("FAIL: Focus an Outlook test compose and allow Accessibility for the terminal running this test.")
            exit(1)
        }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        guard let editor = FocusedEditor.resolve(app: ax, pid: app.processIdentifier, bundleID: FocusedEditor.outlookID),
              FocusedEditor.string(editor, "AXDOMIdentifier") == FocusedEditor.outlookBodyID,
              let window = FocusedEditor.element(editor, kAXWindowAttribute) else {
            print("FAIL: Focus the message body, not the subject, recipients, toolbar or inbox.")
            exit(1)
        }
        let subject = FocusedEditor.search(roots: [window], maxNodes: 300, children: {
            FocusedEditor.attribute($0, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }, matches: { FocusedEditor.string($0, kAXDescriptionAttribute) == "Subject" })
        guard let subject, FocusedEditor.string(subject, kAXValueAttribute) == marker,
              let before = FocusedEditor.string(editor, kAXValueAttribute),
              before.hasPrefix("Their going to the store tomorow. He dont agree.") else {
            print("FAIL: This is not the exact marked test draft. Nothing was changed.")
            exit(1)
        }
        let recipient = FocusedEditor.search(roots: [window], maxNodes: 300, children: {
            FocusedEditor.attribute($0, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }, matches: {
            (FocusedEditor.string($0, kAXDescriptionAttribute) ?? "").contains("Recipients")
                && !(FocusedEditor.string($0, kAXValueAttribute) ?? "").isEmpty
                && FocusedEditor.string($0, kAXRoleAttribute) == "AXTextField"
        })
        guard recipient == nil else { print("FAIL: Test draft contains recipients. Nothing was changed."); exit(1) }
        print("PASS: Resolved the actual Outlook WebKit compose body.")
        let range = (before as NSString).range(of: "tomorow")
        var cfRange = CFRange(location: range.location, length: range.length)
        var bounds: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(editor, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                               AXValueCreate(.cfRange, &cfRange)!, &bounds)
        guard result == .success, let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() else {
            print("FAIL: No word coordinates for inline underlines."); exit(1)
        }
        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0 else {
            print("FAIL: Empty word coordinates."); exit(1)
        }
        print("PASS: Obtained word coordinates for inline underlines.")
        let clipboardTypes = NSPasteboard.general.types
        let clipboardText = NSPasteboard.general.string(forType: .string)
        let ok = await AccessibilityEdit.apply(editor: editor, appPID: app.processIdentifier, bundleID: app.bundleIdentifier!,
                                               snapshot: before, range: range, original: "tomorow", replacement: "tomorrow")
        guard ok, FocusedEditor.string(editor, kAXValueAttribute) == before.replacingOccurrences(of: "tomorow", with: "tomorrow") else {
            print("FAIL: Correction was not verified.")
            print("Active target:", NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier)
            print("Selection:", String(describing: AccessibilityEdit.selection(editor)))
            print("Selected expected word:", FocusedEditor.string(editor, kAXSelectedTextAttribute) == "tomorow")
            print("Body unchanged:", FocusedEditor.string(editor, kAXValueAttribute) == before)
            exit(1)
        }
        print("PASS: Replaced only tomorow → tomorrow; remaining body and signature unchanged.")
        guard clipboardTypes == NSPasteboard.general.types, clipboardText == NSPasteboard.general.string(forType: .string) else {
            print("FAIL: Clipboard was not restored."); exit(1)
        }
        print("PASS: Clipboard restored. No email sent.")
    }
}
