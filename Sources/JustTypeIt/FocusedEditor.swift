// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import AppKit
import ApplicationServices

/// Resolves hosted editors without mistaking a reading pane, search field or recipient for a draft.
@MainActor
enum FocusedEditor {
    static let outlookID = "com.microsoft.Outlook"
    static let outlookBodyID = "ms-outlook-mac-text-editor"

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    static func element(_ source: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(source, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func belongsToApp(_ editor: AXUIElement, pid: pid_t) -> Bool {
        var owner: pid_t = 0
        if AXUIElementGetPid(editor, &owner) == .success, owner == pid { return true }
        // Outlook's body belongs to WebKit, but its containing window belongs to Outlook.
        guard let window = element(editor, kAXWindowAttribute) ?? element(editor, kAXTopLevelUIElementAttribute) else { return false }
        return AXUIElementGetPid(window, &owner) == .success && owner == pid
    }

    static func isTextField(role: String, subrole: String, description: String) -> Bool {
        guard role != "AXSecureTextField", subrole != "AXSecureTextField" else { return false }
        guard ["AXTextArea", "AXTextField", "AXComboBox"].contains(role) else { return false }
        if role != "AXTextArea" {
            let label = description.lowercased()
            if ["search", "address", "url", "password", "recipient", "find"].contains(where: label.contains) { return false }
        }
        return true
    }

    private static func isTextField(_ element: AXUIElement) -> Bool {
        let role = string(element, kAXRoleAttribute) ?? ""
        let subrole = string(element, kAXSubroleAttribute) ?? ""
        let description = [kAXDescriptionAttribute, kAXPlaceholderValueAttribute, kAXIdentifierAttribute]
            .compactMap { string(element, $0) }.joined(separator: " ")
        return isTextField(role: role, subrole: subrole, description: description)
    }

    /// A bounded, cycle-safe traversal: Office accessibility trees can contain self-children.
    static func search<Node: Hashable>(roots: [Node], maxNodes: Int = 160, maxDepth: Int = 10,
                                      children: (Node) -> [Node], matches: (Node) -> Bool) -> Node? {
        var queue = roots.map { ($0, 0) }
        var cursor = 0
        var seen = Set<Node>()
        while cursor < queue.count, seen.count < maxNodes {
            let (node, depth) = queue[cursor]
            cursor += 1
            guard seen.insert(node).inserted else { continue }
            if matches(node) { return node }
            guard depth < maxDepth else { continue }
            let remaining = max(0, maxNodes - queue.count)
            queue += children(node).prefix(remaining).map { ($0, depth + 1) }
        }
        return nil
    }

    private static func children(_ node: AXUIElement) -> [AXUIElement] {
        (attribute(node, kAXChildrenAttribute) as? [AXUIElement])
            ?? (attribute(node, "AXChildrenInNavigationOrder") as? [AXUIElement]) ?? []
    }

    static func resolve(app: AXUIElement, pid: pid_t, bundleID: String) -> AXUIElement? {
        let nativeFocus = element(app, kAXFocusedUIElementAttribute)
        if let focus = nativeFocus, isTextField(focus), belongsToApp(focus, pid: pid) { return focus }

        // System focus can reach the WebKit child even if Outlook's app-level focus is nil.
        let systemFocus = element(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute)
        if let focus = systemFocus, isTextField(focus), belongsToApp(focus, pid: pid) { return focus }
        guard bundleID == outlookID else { return nil }

        // Outlook sometimes focuses a paragraph or its native "Editor" host instead of the text area.
        for focus in [systemFocus, nativeFocus].compactMap({ $0 }) where belongsToApp(focus, pid: pid) {
            var parent: AXUIElement? = focus
            var visited = Set<AXUIElement>()
            while let node = parent, visited.count < 8, visited.insert(node).inserted {
                if string(node, "AXDOMIdentifier") == outlookBodyID, isTextField(node) { return node }
                parent = element(node, "AXEditableAncestor") ?? element(node, kAXParentAttribute)
            }
        }

        // Search only the active window, and only accept the actual focused Outlook compose body.
        // Never pick a nonfocused draft or an email being read in the inbox.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let window = element(app, kAXFocusedWindowAttribute) ?? element(app, kAXMainWindowAttribute)
                ?? (attribute(app, kAXWindowsAttribute) as? [AXUIElement])?.first else { return nil }
        return search(roots: [window], children: children) { node in
            string(node, "AXDOMIdentifier") == outlookBodyID
                && (attribute(node, kAXFocusedAttribute) as? Bool) == true
                && isTextField(node) && belongsToApp(node, pid: pid)
        }
    }
}
