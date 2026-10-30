// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import AppKit
import ApplicationServices

/// A correction is successful only when the complete text matches the expected result.
/// WebKit/Outlook can return AX success for a replacement without actually making it.
@MainActor
enum AccessibilityEdit {
    static func expectedText(_ text: String, range: NSRange, original: String, replacement: String) -> String? {
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
              range.location <= text.utf16.count, range.length <= text.utf16.count - range.location,
              let valid = Range(range, in: text), text.indices.contains(valid.lowerBound) || valid.lowerBound == text.endIndex,
              text.indices.contains(valid.upperBound) || valid.upperBound == text.endIndex,
              String(text[valid]) == original else { return nil }
        return (text as NSString).replacingCharacters(in: range, with: replacement)
    }

    static func selection(_ editor: AXUIElement) -> NSRange? {
        guard let value = FocusedEditor.attribute(editor, kAXSelectedTextRangeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    static func apply(editor: AXUIElement, appPID: pid_t, bundleID: String,
                      snapshot: String, range: NSRange, original: String, replacement: String) async -> Bool {
        let debug = ProcessInfo.processInfo.environment["JTI_EDIT_DEBUG"] == "1"
        if debug { print("edit: target active", targetIsActive(editor, pid: appPID, bundleID: bundleID)) }
        guard let expected = expectedText(snapshot, range: range, original: original, replacement: replacement),
              snapshot != expected, targetIsActive(editor, pid: appPID, bundleID: bundleID),
              FocusedEditor.string(editor, kAXValueAttribute) == snapshot else { return false }
        if bundleID == FocusedEditor.outlookID {
            AXUIElementSetAttributeValue(editor, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange),
              AXUIElementSetAttributeValue(editor, kAXSelectedTextRangeAttribute as CFString, value) == .success else { return false }
        // Wait for the hosted editor to acknowledge selection before inserting anything.
        for _ in 0..<5 {
            if selection(editor) == range { break }
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        if debug { print("edit: selected", selection(editor) == range, "target active", targetIsActive(editor, pid: appPID, bundleID: bundleID)) }
        guard selection(editor) == range, targetIsActive(editor, pid: appPID, bundleID: bundleID),
              FocusedEditor.string(editor, kAXValueAttribute) == snapshot else { return false }
        if bundleID == FocusedEditor.outlookID { try? await Task.sleep(nanoseconds: 100_000_000) }

        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(editor, kAXSelectedTextAttribute as CFString, &settable)
        // Outlook's AXSelectedText setter is a no-op; use verified selection + paste directly.
        if bundleID != FocusedEditor.outlookID, settable.boolValue {
            AXUIElementSetAttributeValue(editor, kAXSelectedTextAttribute as CFString, replacement as CFString)
            for _ in 0..<5 {
                let after = FocusedEditor.string(editor, kAXValueAttribute)
                if after == expected { return true }
                if after != snapshot { return false }
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
        }
        guard !Task.isCancelled, selection(editor) == range,
              targetIsActive(editor, pid: appPID, bundleID: bundleID),
              FocusedEditor.string(editor, kAXValueAttribute) == snapshot else { return false }
        if debug { print("edit: posting paste", CGPreflightPostEventAccess()) }

        let pasteboard = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (pasteboard.pasteboardItems ?? []).map { item in
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { if let bytes = item.data(forType: type) { data[type] = bytes } }
            return data
        }
        var ownedChange: Int?
        defer {
            // Don't overwrite something the user copied while the paste was in flight.
            if let ownedChange, pasteboard.changeCount == ownedChange {
                pasteboard.clearContents()
                let items = saved.map { data -> NSPasteboardItem in
                    let item = NSPasteboardItem()
                    for (type, bytes) in data { item.setData(bytes, forType: type) }
                    return item
                }
                if !items.isEmpty { pasteboard.writeObjects(items) }
            }
        }
        if replacement.isEmpty {
            sendKey(51, flags: [])
        } else {
            pasteboard.clearContents()
            pasteboard.setString(replacement, forType: .string)
            ownedChange = pasteboard.changeCount
            sendKey(9, flags: .maskCommand)
        }
        for _ in 0..<15 {
            try? await Task.sleep(nanoseconds: 40_000_000)
            let after = FocusedEditor.string(editor, kAXValueAttribute)
            if after == expected { return true }
            if after != snapshot { return false }
        }
        if debug { print("edit: timed out") }
        return false
    }

    private static func targetIsActive(_ editor: AXUIElement, pid: pid_t, bundleID: String) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              FocusedEditor.belongsToApp(editor, pid: pid) else { return false }
        let app = AXUIElementCreateApplication(pid)
        if let focus = FocusedEditor.resolve(app: app, pid: pid, bundleID: bundleID), CFEqual(focus, editor) { return true }
        // Selecting a WebKit range can temporarily drop AXFocused. Only allow this exact
        // Outlook body when its window is still frontmost and no other control owns focus.
        guard bundleID == FocusedEditor.outlookID,
              FocusedEditor.string(editor, "AXDOMIdentifier") == FocusedEditor.outlookBodyID,
              let window = FocusedEditor.element(editor, kAXWindowAttribute),
              let frontWindow = (FocusedEditor.attribute(app, kAXWindowsAttribute) as? [AXUIElement])?.first,
              CFEqual(window, frontWindow) else { return false }
        for source in [app, AXUIElementCreateSystemWide()] {
            if let focus = FocusedEditor.element(source, kAXFocusedUIElementAttribute), !CFEqual(focus, editor) {
                return false
            }
        }
        return true
    }

    private static func sendKey(_ code: CGKeyCode, flags: CGEventFlags) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}
