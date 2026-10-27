// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import AppKit
import ApplicationServices
import SwiftUI

/// Checks the text box you're typing in, in any app, and draws underlines over it.
/// Uses the macOS Accessibility API to read the focused text field and the screen
/// position of each word; click an underline to see the fix.
@MainActor
final class Everywhere: ObservableObject {
    static let shared = Everywhere()

    @Published private(set) var running = false
    @Published private(set) var currentApp = ""
    @Published private(set) var issueCount = 0

    private var timer: Timer?
    private var element: AXUIElement?
    private var pid: pid_t = 0
    private var bundleID = ""
    private var lastText = ""
    private var textOffset = 0
    private var issues: [Issue] = []
    private var rects: [(Issue, [NSRect])] = []
    private var lastEdit = Date.distantPast
    private var checkedText: String?
    private var dismissed: Set<String> = []
    private var mouseMonitor: Any?
    private var enhancedPIDs: Set<pid_t> = []

    private let overlay = OverlayWindow()
    private let badge = BadgePanel()
    private let card = CardPanel()

    static let defaultExcluded: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.microsoft.VSCode", "com.apple.dt.Xcode", "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed", "com.apple.keychainaccess",
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop", "ai.opencode.desktop",
    ]

    var isTrusted: Bool { AXIsProcessTrusted() }

    func start() {
        guard timer == nil else { return }
        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
        running = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            MainActor.assumeIsolated { Everywhere.shared.tick() }
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { e in
            let p = NSEvent.mouseLocation
            MainActor.assumeIsolated { Everywhere.shared.clicked(at: p) }
            _ = e
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let m = mouseMonitor { NSEvent.removeMonitor(m) }
        mouseMonitor = nil
        running = false
        hideAll()
    }

    private func hideAll() {
        overlay.orderOut(nil)
        badge.orderOut(nil)
        card.orderOut(nil)
        rects = []
        issueCount = 0
    }

    // MARK: Polling

    private func tick() {
        guard AXIsProcessTrusted() else { hideAll(); return }
        guard let app = NSWorkspace.shared.frontmostApplication else { hideAll(); return }
        let bid = app.bundleIdentifier ?? ""
        if bid == Bundle.main.bundleIdentifier {
            // Our own suggestion card is interactive; keep it, hide the rest.
            if !card.isVisible { overlay.orderOut(nil); badge.orderOut(nil) }
            return
        }
        let prefs = Store.shared.prefs
        if Everywhere.defaultExcluded.contains(bid) || prefs.excludedApps.contains(bid) { hideAll(); currentApp = app.localizedName ?? ""; return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        if !enhancedPIDs.contains(app.processIdentifier) {
            // Chromium and Electron apps (Chrome, Edge, Slack, Teams, Notion…) only expose web text when asked.
            AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            if ["com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera"].contains(bid) {
                AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            }
            enhancedPIDs.insert(app.processIdentifier)
        }
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        guard let el = focusedTextElement(axApp) else { hideAll(); element = nil; return }
        if element == nil || !CFEqual(el, element!) || pid != app.processIdentifier {
            element = el
            pid = app.processIdentifier
            bundleID = bid
            currentApp = app.localizedName ?? ""
            lastText = ""
            checkedText = nil
            issues = []
            card.orderOut(nil)
        }
        guard let full = string(el, kAXValueAttribute) else { hideAll(); return }
        if full != lastText {
            lastText = full
            lastEdit = Date()
            card.orderOut(nil)
        }
        // Check after a short pause in typing.
        if checkedText != full, Date().timeIntervalSince(lastEdit) > 0.45 {
            runCheck(full, element: el)
        }
        layout(el)
    }

    private func focusedTextElement(_ axApp: AXUIElement) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &v) == .success, let v else { return nil }
        let el = v as! AXUIElement
        let role = string(el, kAXRoleAttribute) ?? ""
        let sub = string(el, kAXSubroleAttribute) ?? ""
        if sub == "AXSecureTextField" || role == "AXSecureTextField" { return nil }
        let textRoles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox"]
        var editable = textRoles.contains(role)
        if !editable {
            var e: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, "AXEditable" as CFString, &e) == .success, (e as? Bool) == true { editable = true }
        }
        guard editable else { return nil }
        // Single-line search/URL fields aren't worth checking.
        if role == "AXTextField" || role == "AXComboBox" {
            let desc = ((string(el, kAXDescriptionAttribute) ?? "") + (string(el, kAXPlaceholderValueAttribute) ?? "") + (string(el, kAXIdentifierAttribute) ?? "")).lowercased()
            if ["search", "address", "url", "password", "email address", "find"].contains(where: desc.contains) { return nil }
        }
        return el
    }

    private func string(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    private func selectedRange(_ el: AXUIElement) -> NSRange? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &v) == .success, let v,
              CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var r = CFRange()
        guard AXValueGetValue(v as! AXValue, .cfRange, &r) else { return nil }
        return NSRange(location: r.location, length: r.length)
    }

    // MARK: Checking

    private func runCheck(_ full: String, element el: AXUIElement) {
        checkedText = full
        let ns = full as NSString
        guard ns.length > 0, TextUtil.wordCount(full) >= 2 else { issues = []; return }
        // Long documents: check the region around the cursor.
        var offset = 0
        var text = full
        let window = 6000
        if ns.length > window * 2 {
            let caret = selectedRange(el)?.location ?? 0
            var start = max(0, caret - window)
            var end = min(ns.length, caret + window)
            let before = ns.substring(to: start)
            if let p = before.range(of: "\n", options: .backwards) { start = (before as NSString).length - (String(before[p.upperBound...]) as NSString).length }
            let tail = ns.substring(from: end)
            if let p = tail.range(of: "\n") { end += (String(tail[..<p.lowerBound]) as NSString).length }
            offset = start
            text = ns.substring(with: NSRange(location: start, length: end - start))
        }
        var opts = CheckOptions.from(Store.shared.prefs, goals: goalsForApp())
        opts.consistency = false
        let found = RuleEngine.check(text, options: opts)
            .filter { !dismissed.contains(key($0)) }
            .filter { $0.kind != "Engagement/Repetition" && $0.kind != "Style/Clarity/LongSentence" }
            .map { i -> Issue in var i = i; i.range.location += offset; return i }
        // Don't flag the word being typed right now.
        let caret = selectedRange(el)?.location ?? -1
        issues = found.filter { i in
            !(NSMaxRange(i.range) == caret && i.kind.hasPrefix("Spelling") && caret == ns.length)
        }
        textOffset = offset
    }

    private func goalsForApp() -> Goals {
        var g = Store.shared.prefs.defaultGoals
        let mail = ["com.microsoft.Outlook", "com.apple.mail", "com.readdle.smartemail-Mac", "com.superhuman.electron"]
        let chat = ["com.tinyspeck.slackmacgap", "com.microsoft.teams2", "com.apple.MobileSMS", "net.whatsapp.WhatsApp", "com.hnc.Discord"]
        if mail.contains(bundleID) { g.domain = .email; g.formality = .neutral }
        if chat.contains(bundleID) { g.domain = .casual; g.formality = .informal }
        if bundleID == "com.microsoft.Word" || bundleID == "com.apple.iWork.Pages" { g.domain = .general }
        return g
    }

    private func key(_ i: Issue) -> String { "\(i.kind)|\(i.original.lowercased())" }

    // MARK: Drawing

    private func layout(_ el: AXUIElement) {
        guard !issues.isEmpty, lastText == checkedText else {
            overlay.orderOut(nil)
            if issues.isEmpty { badge.orderOut(nil) }
            issueCount = issues.count
            return
        }
        guard let frame = elementFrame(el) else { hideAll(); return }
        let visible = frame.insetBy(dx: -2, dy: -2)
        var out: [(Issue, [NSRect])] = []
        let ns = lastText as NSString
        let caret = selectedRange(el)?.location ?? 0
        let nearby = issues.sorted { abs($0.range.location - caret) < abs($1.range.location - caret) }.prefix(80)
        for i in nearby where NSMaxRange(i.range) <= ns.length {
            guard TextUtil.substring(lastText, i.range) == i.original else { continue }
            let rs = lineRects(el, i.range).filter { visible.intersects($0) && $0.width > 0 && $0.height > 0 && $0.height < 80 }
            if !rs.isEmpty { out.append((i, rs)) }
        }
        rects = out
        issueCount = issues.count
        if out.isEmpty { overlay.orderOut(nil) } else { overlay.show(frame: frame, marks: out.map { ($0.0.group.nsColor, $0.1, $0.0.range.length > 40) }) }
        badge.show(count: issues.count, worst: issues.contains { $0.group == .correctness } ? IssueGroup.correctness : (issues.first?.group ?? .clarity), near: frame)
    }

    private func elementFrame(_ el: AXUIElement) -> NSRect? {
        var p: CFTypeRef?, s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &s) == .success, let p, let s else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &pt)
        AXValueGetValue(s as! AXValue, .cgSize, &sz)
        guard sz.width > 10, sz.height > 8 else { return nil }
        var r = toCocoa(CGRect(origin: pt, size: sz))
        // Web and Office editors report the whole scrollable page; clip to the visible window.
        if let w = windowFrame(el) { r = r.intersection(w) }
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(r) }) { r = r.intersection(screen.visibleFrame) }
        return r.isEmpty ? nil : r
    }

    private func windowFrame(_ el: AXUIElement) -> NSRect? {
        var w: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXWindowAttribute as CFString, &w) == .success, let w else { return nil }
        let win = w as! AXUIElement
        var p: CFTypeRef?, s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &s) == .success, let p, let s else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &pt)
        AXValueGetValue(s as! AXValue, .cgSize, &sz)
        return toCocoa(CGRect(origin: pt, size: sz))
    }

    /// One rect per line for a range (handles wrapped phrases).
    private func lineRects(_ el: AXUIElement, _ range: NSRange) -> [NSRect] {
        guard let whole = bounds(el, range) else { return [] }
        if whole.height < 30 || range.length < 3 { return [whole] }
        // Spans multiple lines: measure each word.
        var out: [NSRect] = []
        let text = TextUtil.substring(lastText, range)
        for w in TextUtil.words(text) {
            if let r = bounds(el, NSRange(location: range.location + w.range.location, length: w.range.length)) {
                if let last = out.last, abs(last.minY - r.minY) < 3 { out[out.count - 1] = last.union(r) } else { out.append(r) }
            }
        }
        return out
    }

    private func bounds(_ el: AXUIElement, _ range: NSRange) -> NSRect? {
        var r = CFRange(location: range.location, length: range.length)
        guard let v = AXValueCreate(.cfRange, &r) else { return nil }
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(el, kAXBoundsForRangeParameterizedAttribute as CFString, v, &out) == .success, let out else { return nil }
        var rect = CGRect.zero
        AXValueGetValue(out as! AXValue, .cgRect, &rect)
        guard rect.width > 0 || rect.height > 0 else { return nil }
        return toCocoa(rect)
    }

    /// Accessibility uses top-left origin; AppKit uses bottom-left of the primary screen.
    private func toCocoa(_ r: CGRect) -> NSRect {
        let h = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }

    // MARK: Interaction

    private func clicked(at p: NSPoint) {
        if card.isVisible, card.frame.contains(p) { return }
        if badge.isVisible, badge.frame.contains(p) { return }
        guard let hit = rects.first(where: { $0.1.contains { $0.insetBy(dx: -2, dy: -4).contains(p) } }) else {
            card.orderOut(nil)
            return
        }
        showCard(hit.0, below: hit.1.first!)
    }

    func showAllFromBadge() {
        guard let first = issues.first(where: { i in rects.contains { $0.0.id == i.id } }) ?? issues.first else { return }
        let anchor = rects.first { $0.0.id == first.id }?.1.first ?? badge.frame
        showCard(first, below: anchor)
    }

    private func showCard(_ issue: Issue, below anchor: NSRect) {
        let idx = issues.firstIndex { $0.id == issue.id } ?? 0
        let view = EverywhereCard(issue: issue, index: idx, total: issues.count,
                                  apply: { [weak self] rep in self?.apply(issue, rep) },
                                  dismiss: { [weak self] in self?.dismiss(issue) },
                                  addWord: { [weak self] in Store.shared.addToDictionary(issue.original); self?.recheckNow() },
                                  next: { [weak self] in self?.step(from: issue, by: 1) },
                                  previous: { [weak self] in self?.step(from: issue, by: -1) },
                                  openInApp: { [weak self] in self?.openInApp() })
        card.show(view, below: anchor)
    }

    private func step(from issue: Issue, by d: Int) {
        guard let i = issues.firstIndex(where: { $0.id == issue.id }), !issues.isEmpty else { return }
        let n = issues[(i + d + issues.count) % issues.count]
        let anchor = rects.first { $0.0.id == n.id }?.1.first ?? card.frame.offsetBy(dx: 0, dy: card.frame.height)
        showCard(n, below: anchor)
    }

    private func recheckNow() {
        checkedText = nil
        card.orderOut(nil)
    }

    private func dismiss(_ issue: Issue) {
        dismissed.insert(key(issue))
        issues.removeAll { $0.id == issue.id }
        Store.shared.stats.suggestionsDismissed += 1
        card.orderOut(nil)
        if let el = element { layout(el) }
    }

    private func openInApp() {
        card.orderOut(nil)
        let d = Document(title: "From \(currentApp)", text: lastText, goals: goalsForApp())
        Store.shared.documents.insert(d, at: 0)
        NotificationCenter.default.post(name: .loadDocument, object: d.id)
        AppDelegate.openMain()
    }

    /// Replaces the flagged text inside the other app.
    private func apply(_ issue: Issue, _ replacement: String) {
        card.orderOut(nil)
        guard let el = element, let current = string(el, kAXValueAttribute),
              TextUtil.substring(current, issue.range) == issue.original else { recheckNow(); return }
        var rep = replacement
        var range = issue.range
        if rep.isEmpty {
            let ns = current as NSString
            if NSMaxRange(range) < ns.length, ns.substring(with: NSRange(location: NSMaxRange(range), length: 1)) == " ", !issue.original.hasSuffix(" ") {
                range.length += 1
            }
            let start = range.location == 0 || ".!?\n".contains(ns.substring(with: NSRange(location: max(0, range.location - 2), length: min(2, range.location))).last(where: { $0 != " " }) ?? ".")
            if start, NSMaxRange(range) < ns.length {
                let next = ns.substring(with: NSRange(location: NSMaxRange(range), length: 1))
                range.length += 1
                rep = next.uppercased()
            }
        }
        var cf = CFRange(location: range.location, length: range.length)
        guard let rv = AXValueCreate(.cfRange, &cf) else { return }
        AXUIElementSetAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, rv)
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(el, kAXSelectedTextAttribute as CFString, &settable)
        var done = false
        if settable.boolValue, AXUIElementSetAttributeValue(el, kAXSelectedTextAttribute as CFString, rep as CFString) == .success {
            let after = string(el, kAXValueAttribute) ?? ""
            done = after != current && (after as NSString).length == (current as NSString).length - range.length + (rep as NSString).length
        }
        if !done { paste(rep) }
        Store.shared.recordAccept(issue)
        issues.removeAll { $0.id == issue.id }
        checkedText = nil
        lastEdit = Date().addingTimeInterval(-1)
    }

    private func paste(_ s: String) {
        let pb = NSPasteboard.general
        let saved = pb.pasteboardItems?.compactMap { item -> [NSPasteboard.PasteboardType: Data]? in
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let v = item.data(forType: t) { d[t] = v } }
            return d
        } ?? []
        pb.clearContents()
        if s.isEmpty {
            // Deleting: send Delete instead of pasting nothing.
            key(51, flags: [])
        } else {
            pb.setString(s, forType: .string)
            pb.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
            key(9, flags: .maskCommand)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            pb.clearContents()
            let items: [NSPasteboardItem] = saved.map { d in let it = NSPasteboardItem(); for (t, v) in d { it.setData(v, forType: t) }; return it }
            if !items.isEmpty { pb.writeObjects(items) }
        }
    }

    private func key(_ code: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let d = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)
        let u = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
        d?.flags = flags
        u?.flags = flags
        d?.post(tap: .cghidEventTap)
        u?.post(tap: .cghidEventTap)
    }
}

extension Notification.Name {
    static let loadDocument = Notification.Name("jti.loadDocument")
}

// MARK: Windows

/// Transparent, click-through window that draws the underlines.
final class OverlayWindow: NSWindow {
    private let canvas = UnderlineView()

    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        contentView = canvas
    }

    func show(frame: NSRect, marks: [(NSColor, [NSRect], Bool)]) {
        if self.frame != frame { setFrame(frame, display: false) }
        canvas.marks = marks.map { m in (m.0, m.1.map { NSRect(x: $0.minX - frame.minX, y: $0.minY - frame.minY, width: $0.width, height: $0.height) }, m.2) }
        canvas.needsDisplay = true
        if !isVisible { orderFrontRegardless() }
    }
}

final class UnderlineView: NSView {
    var marks: [(NSColor, [NSRect], Bool)] = []

    override func draw(_ dirtyRect: NSRect) {
        for (color, rects, dotted) in marks {
            for r in rects {
                let y = r.minY + 0.5
                let p = NSBezierPath()
                p.lineWidth = dotted ? 1.5 : 2.2
                p.lineCapStyle = .round
                if dotted { p.setLineDash([2, 3], count: 2, phase: 0) }
                p.move(to: NSPoint(x: r.minX, y: y))
                p.line(to: NSPoint(x: r.maxX, y: y))
                color.withAlphaComponent(0.9).setStroke()
                p.stroke()
                if !dotted {
                    color.withAlphaComponent(0.08).setFill()
                    NSBezierPath(roundedRect: r.insetBy(dx: -1, dy: 0), xRadius: 2, yRadius: 2).fill()
                }
            }
        }
    }
}

/// Panels that don't take focus away from the app you're typing in.
class FloatingPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class BadgePanel: FloatingPanel {
    private var count = -1
    private var group: IssueGroup = .correctness

    func show(count: Int, worst: IssueGroup, near frame: NSRect) {
        let size: CGFloat = 26
        var origin = NSPoint(x: frame.maxX - size - 6, y: frame.minY + 6)
        if frame.height > 400 { origin.y = max(frame.minY + 6, frame.minY + 6) }
        if count != self.count || worst != group {
            self.count = count
            group = worst
            let v = FirstMouseHostingView(rootView: BadgeView(count: count, color: worst.color) {
                MainActor.assumeIsolated { Everywhere.shared.showAllFromBadge() }
            })
            v.frame = NSRect(x: 0, y: 0, width: size, height: size)
            contentView = v
        }
        let f = NSRect(origin: origin, size: NSSize(width: size, height: size))
        if self.frame != f { setFrame(f, display: true) }
        if !isVisible { orderFrontRegardless() }
    }
}

struct BadgeView: View {
    let count: Int
    let color: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(color)
                Text(count > 99 ? "99+" : "\(count)").font(.system(size: count > 9 ? 10 : 12, weight: .bold)).foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .help("Just Type It: \(count) suggestion\(count == 1 ? "" : "s")")
    }
}

final class CardPanel: FloatingPanel {
    func show<V: View>(_ view: V, below anchor: NSRect) {
        let host = FirstMouseHostingView(rootView: AnyView(view.frame(width: 330)))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        contentView = host
        var origin = NSPoint(x: anchor.minX - 10, y: anchor.minY - size.height - 6)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor.origin) }) ?? NSScreen.main {
            let vf = screen.visibleFrame
            if origin.y < vf.minY { origin.y = anchor.maxY + 6 }
            origin.x = min(max(vf.minX + 4, origin.x), vf.maxX - size.width - 4)
        }
        setFrame(NSRect(origin: origin, size: size), display: true)
        orderFrontRegardless()
    }
}

struct EverywhereCard: View {
    let issue: Issue
    let index: Int
    let total: Int
    let apply: (String) -> Void
    let dismiss: () -> Void
    let addWord: () -> Void
    let next: () -> Void
    let previous: () -> Void
    let openInApp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Circle().fill(issue.group.color).frame(width: 8, height: 8)
                Text(issue.group.label.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text("·").foregroundStyle(.secondary)
                Text(issue.title).font(.caption.weight(.semibold))
                Spacer()
                if total > 1 {
                    Button(action: previous) { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                    Text("\(index + 1)/\(total)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    Button(action: next) { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
                }
            }
            if issue.range.length <= 80 {
                Text(issue.original).strikethrough(!issue.replacements.isEmpty).foregroundStyle(.secondary).lineLimit(3)
            }
            if !issue.replacements.isEmpty {
                FlowButtons(options: issue.replacements, color: issue.group.color, action: apply)
            }
            Text(issue.explanation).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack(spacing: 14) {
                Button(action: dismiss) { Label("Dismiss", systemImage: "xmark") }
                if issue.kind.hasPrefix("Spelling") {
                    Button(action: addWord) { Label("Add to dictionary", systemImage: "book") }
                }
                Spacer()
                Button(action: openInApp) { Image(systemName: "arrow.up.forward.app") }.help("Open in Just Type It for tone, rewrites and AI tools")
            }
            .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1)))
        .padding(1)
    }
}
