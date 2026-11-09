// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import SwiftUI

/// Rewrite styles offered for highlighted text, in any app.
enum RewriteMode: String, CaseIterable, Identifiable {
    case improve, professional, casual, shorter, longer, enthusiastic, friendly, confident, clearer, simpler,
         formal, diplomatic, persuasive, grammarOnly, bullets, summarize, reply
    var id: String { rawValue }

    var label: String {
        switch self {
        case .improve: "Improve it"
        case .professional: "More professional"
        case .casual: "More casual"
        case .shorter: "Shorter"
        case .longer: "Longer"
        case .enthusiastic: "More enthusiastic"
        case .friendly: "Friendlier"
        case .confident: "More confident"
        case .clearer: "Clearer"
        case .simpler: "Simpler"
        case .formal: "More formal"
        case .diplomatic: "More diplomatic"
        case .persuasive: "More persuasive"
        case .grammarOnly: "Fix grammar only"
        case .bullets: "Bullet points"
        case .summarize: "Summarize"
        case .reply: "Write a reply"
        }
    }

    var icon: String {
        switch self {
        case .improve: "wand.and.stars"
        case .professional: "briefcase"
        case .casual: "cup.and.saucer"
        case .shorter: "arrow.down.right.and.arrow.up.left"
        case .longer: "arrow.up.left.and.arrow.down.right"
        case .enthusiastic: "party.popper"
        case .friendly: "face.smiling"
        case .confident: "bolt"
        case .clearer: "eye"
        case .simpler: "textformat.size.smaller"
        case .formal: "building.columns"
        case .diplomatic: "hand.raised"
        case .persuasive: "megaphone"
        case .grammarOnly: "checkmark.circle"
        case .bullets: "list.bullet"
        case .summarize: "text.alignleft"
        case .reply: "arrowshape.turn.up.left"
        }
    }

    /// The modes shown first; the rest are under "More".
    static let primary: [RewriteMode] = [.improve, .professional, .casual, .shorter, .enthusiastic, .friendly, .confident, .grammarOnly]

    var instruction: String {
        switch self {
        case .improve: "Improve the text: fix every error and make it clearer, smoother and more engaging, keeping the meaning and the author's voice."
        case .professional: "Rewrite the text so it sounds professional and polished, suitable for work."
        case .casual: "Rewrite the text in a relaxed, casual, conversational tone."
        case .shorter: "Rewrite the text much shorter and more concise, keeping every key point."
        case .longer: "Rewrite the text so it is about twice as long: use complete, well-punctuated sentences, explain the reason a little more and add a polite closing. Do not invent names, dates or numbers."
        case .enthusiastic: "Rewrite the text so it sounds warm, upbeat and enthusiastic."
        case .friendly: "Rewrite the text so it sounds warm, kind and friendly."
        case .confident: "Rewrite the text so it sounds confident and assertive: remove hedging like 'I think', 'maybe', 'just'."
        case .clearer: "Rewrite the text so it is as clear and easy to follow as possible."
        case .simpler: "Rewrite the text in simple, plain English that anyone can understand."
        case .formal: "Rewrite the text in a formal register."
        case .diplomatic: "Rewrite the text so it is tactful and diplomatic, softening anything that could sound blunt."
        case .persuasive: "Rewrite the text so it is more persuasive and compelling."
        case .grammarOnly: "Correct every spelling, grammar, capitalization and punctuation mistake (for example 'alot' → 'a lot', 'cant' → 'can't', 'i' → 'I', 'u' → 'you'). Keep the same words otherwise."
        case .bullets: "Turn the text into a short list of clear bullet points starting with '- '."
        case .summarize: "Summarize the text in one to three sentences."
        case .reply: "The text is a message the user received. Write a helpful, polite reply in the user's voice (first person). Never use placeholders like [Name]."
        }
    }

    /// Modes that also work without Apple Intelligence (rule-based).
    var worksOffline: Bool { self == .grammarOnly || self == .shorter || self == .confident }
}

/// Produces rewrites: Apple Intelligence when available, rules otherwise.
@MainActor
enum Rewriter {
    static func versions(of text: String, mode: RewriteMode, custom: String? = nil, count: Int = 3) async -> [String] {
        let instruction = custom.map { "Rewrite the text following this instruction: \($0)" } ?? mode.instruction
        var out: [String] = []
        if AIEngine.available {
            let goals = Store.shared.prefs.defaultGoals
            let brand = Store.shared.prefs.brandTone
            // First version: deterministic. Others: varied wording.
            if let a = await AIEngine.transform(text, instruction, goals: goals, brand: brand) { out.append(clean(a)) }
            if count > 1 && mode != .grammarOnly && mode != .summarize {
                let ins = instruction + "\nKeep the original language. Do not invent facts. Output ONLY the resulting text, with no commentary or quotes."
                for _ in 1..<count {
                    if let b = await AIEngine.run(ins, "TEXT:\n<<<\n\(text)\n>>>", temperature: 0.8) {
                        let v = clean(b)
                        if !out.contains(v) && v != text { out.append(v) }
                    }
                }
            }
        }
        // The model sometimes returns the text unchanged; ask once more, more firmly.
        let unchanged: (String) -> Bool = { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        out.removeAll(where: unchanged)
        if out.isEmpty, AIEngine.available {
            let firm = instruction + "\nThe output MUST be different from the input. Output ONLY the rewritten text."
            if let c = await AIEngine.run(firm, "TEXT:\n<<<\n\(text)\n>>>", temperature: 0.5).map(clean), !unchanged(c) { out.append(c) }
        }
        // Grammar fixes: make sure the rule engine's corrections are applied too.
        if mode == .grammarOnly || mode == .improve || mode == .professional || mode == .formal {
            out = out.map { v in offline(v, mode: .grammarOnly) ?? v }
        }
        if out.isEmpty, let rule = offline(text, mode: mode) { out.append(rule) }
        return out.filter { !$0.isEmpty }
    }

    static func clean(_ s: String) -> String {
        AIEngine.removePlaceholdersForReplies(s).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Rule-based fallback: applies every grammar fix, and for some modes, the matching style fixes.
    static func offline(_ text: String, mode: RewriteMode) -> String? {
        var o = CheckOptions.from(Store.shared.prefs, goals: Store.shared.prefs.defaultGoals)
        o.consistency = false
        let issues = RuleEngine.check(text, options: o).filter { i in
            guard !i.replacements.isEmpty, i.range.length <= 80 else { return false }
            switch mode {
            case .grammarOnly: return i.group == .correctness
            case .shorter: return i.group == .correctness || i.kind.hasPrefix("Style/Wordiness")
            case .confident: return i.group == .correctness || i.kind == "Style/Confidence/Hedging"
            default: return i.group == .correctness || i.group == .clarity
            }
        }.sorted { $0.range.location > $1.range.location }
        var result = text as NSString
        var lastStart = Int.max
        for i in issues where NSMaxRange(i.range) <= lastStart {
            result = result.replacingCharacters(in: i.range, with: i.replacements[0]) as NSString
            lastStart = i.range.location
        }
        let s = TextBrainLite.capitalizeSentences(result as String)
        return s == text ? nil : s
    }
}

enum TextBrainLite {
    static func capitalizeSentences(_ s: String) -> String {
        var out = ""
        var capNext = true
        for ch in s {
            if capNext, ch.isLetter { out.append(contentsOf: ch.uppercased()); capNext = false; continue }
            out.append(ch)
            if ".!?\n".contains(ch) { capNext = true } else if !ch.isWhitespace { capNext = false }
        }
        return out
    }
}

/// ⌃⌥R in any app: rewrite the highlighted text. A small floating button also appears next to
/// a selection of a few words, so it's one click.
@MainActor
final class RewriteAnywhere {
    static let shared = RewriteAnywhere()
    private var panel: NSPanel?
    private var source: (app: NSRunningApplication, element: AXUIElement?, range: NSRange?, text: String)?
    private var hotKeyRef: EventHotKeyRef?
    private let button = SelectionButton()
    private var timer: Timer?
    private var lastSelection = ""

    func install() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if id.id == 2 { RewriteAnywhere.shared.run() } else { QuickCheck.shared.run() }
                }
            }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x4A54_4954), id: 2)
        RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKeyRef)
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { RewriteAnywhere.shared.watchSelection() }
        }
    }

    // MARK: Floating button next to a selection

    private func watchSelection() {
        guard Store.shared.prefs.rewriteButton, AXIsProcessTrusted(), panel?.isVisible != true,
              let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier,
              !Everywhere.defaultExcluded.contains(app.bundleIdentifier ?? "") else { button.orderOut(nil); return }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.2)
        guard let el = FocusedEditor.resolve(app: ax, pid: app.processIdentifier, bundleID: app.bundleIdentifier ?? ""),
              let range = AccessibilityEdit.selection(el), range.length > 0,
              let full = FocusedEditor.string(el, kAXValueAttribute),
              let sel = Range(range, in: full).map({ String(full[$0]) }), TextUtil.wordCount(sel) >= 3 else {
            button.orderOut(nil); lastSelection = ""; return
        }
        guard let rect = selectionRect(el, range) else { button.orderOut(nil); return }
        if sel != lastSelection { lastSelection = sel }
        button.show(near: rect) { [weak self] in self?.run() }
    }

    private func selectionRect(_ el: AXUIElement, _ range: NSRange) -> NSRect? {
        var cf = CFRange(location: range.location, length: min(range.length, 2000))
        guard let v = AXValueCreate(.cfRange, &cf) else { return nil }
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(el, kAXBoundsForRangeParameterizedAttribute as CFString, v, &out) == .success,
              let r = Everywhere.axRect(out), r.width > 0 || r.height > 0 else { return nil }
        let h = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }

    // MARK: Rewrite panel

    func run() {
        button.orderOut(nil)
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        Task {
            // Prefer reading the selection directly (keeps the clipboard untouched); fall back to ⌘C.
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            var element: AXUIElement?
            var range: NSRange?
            var text: String?
            if AXIsProcessTrusted(), let el = FocusedEditor.resolve(app: ax, pid: app.processIdentifier, bundleID: app.bundleIdentifier ?? ""),
               let r = AccessibilityEdit.selection(el), r.length > 0, let full = FocusedEditor.string(el, kAXValueAttribute),
               let rr = Range(r, in: full) {
                element = el; range = r; text = String(full[rr])
            }
            if text == nil { text = await QuickCheck.shared.copySelectionPublic() }
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                QuickCheck.shared.show(text: "", canReplace: false, note: "Highlight some text in any app, then press ⌃⌥R to rewrite it.")
                return
            }
            source = (app, element, range, text)
            show(text)
        }
    }

    private func show(_ text: String) {
        panel?.close()
        let view = RewritePanelView(original: text, aiAvailable: AIEngine.available,
                                    replace: { [weak self] new in self?.replace(with: new) },
                                    copy: { new in
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(new, forType: .string)
                                    },
                                    close: { [weak self] in self?.panel?.close() })
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 560),
                        styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .utilityWindow], backing: .buffered, defer: false)
        p.title = "Just Type It – Rewrite"
        p.isFloatingPanel = true
        p.level = .floating
        p.contentView = NSHostingView(rootView: view)
        p.isReleasedWhenClosed = false
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let m = NSEvent.mouseLocation
            let x = min(max(screen.visibleFrame.minX + 10, m.x - 300), screen.visibleFrame.maxX - 610)
            let y = min(max(screen.visibleFrame.minY + 10, m.y - 580), screen.visibleFrame.maxY - 570)
            p.setFrameOrigin(NSPoint(x: x, y: y))
        } else { p.center() }
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        panel = p
    }

    /// Puts the rewrite back into the original app, replacing exactly the highlighted text.
    private func replace(with new: String) {
        panel?.close()
        guard let src = source else { return }
        src.app.activate()
        Task { @MainActor in
            guard await QuickCheck.waitUntilFrontmost(src.app) else {
                copyWithNotice(new, "Couldn't switch back to \(src.app.localizedName ?? "the app"). The rewrite is on your clipboard; press ⌘V to paste it.")
                return
            }
            if let el = src.element, let range = src.range, let full = FocusedEditor.string(el, kAXValueAttribute),
               TextUtil.substring(full, range) == src.text {
                if await AccessibilityEdit.apply(editor: el, appPID: src.app.processIdentifier, bundleID: src.app.bundleIdentifier ?? "",
                                                 snapshot: full, range: range, original: src.text, replacement: new) {
                    Store.shared.stats.rewrites += 1
                    return
                }
                // Only fall back to pasting if nothing changed and the same text is still selected.
                guard FocusedEditor.string(el, kAXValueAttribute) == full, AccessibilityEdit.selection(el) == range else {
                    copyWithNotice(new, "The text changed before the rewrite could be applied. The rewrite is on your clipboard; press ⌘V to paste it.")
                    return
                }
            }
            QuickCheck.shared.pastePublic(new)
            Store.shared.stats.rewrites += 1
        }
    }
}

/// Puts text on the clipboard and tells the user, when it can't be placed safely.
@MainActor func copyWithNotice(_ text: String, _ message: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    let alert = NSAlert()
    alert.messageText = "Just Type It"
    alert.informativeText = message
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
}

/// Small round button that floats next to selected text.
final class SelectionButton: FloatingPanel {
    private var action: (() -> Void)?

    func show(near rect: NSRect, action: @escaping () -> Void) {
        self.action = action
        if contentView == nil {
            let v = FirstMouseHostingView(rootView: SelectionButtonView { [weak self] in self?.action?() })
            v.frame = NSRect(x: 0, y: 0, width: 30, height: 30)
            contentView = v
        }
        var origin = NSPoint(x: rect.maxX + 4, y: rect.maxY - 4)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(rect.origin) }) ?? NSScreen.main {
            origin.x = min(origin.x, screen.visibleFrame.maxX - 34)
            origin.y = min(max(origin.y, screen.visibleFrame.minY + 4), screen.visibleFrame.maxY - 34)
        }
        let f = NSRect(origin: origin, size: NSSize(width: 30, height: 30))
        if frame != f { setFrame(f, display: true) }
        if !isVisible { orderFrontRegardless() }
    }
}

struct SelectionButtonView: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(red: 0.09, green: 0.72, blue: 0.53), Color(red: 0.05, green: 0.47, blue: 0.62)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "wand.and.stars").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            }
            .shadow(radius: 2)
        }
        .buttonStyle(.plain)
        .help("Rewrite with Just Type It (⌃⌥R)")
    }
}

struct RewritePanelView: View {
    let original: String
    let aiAvailable: Bool
    let replace: (String) -> Void
    let copy: (String) -> Void
    let close: () -> Void

    @VState private var mode: RewriteMode?
    @VState private var versions: [String] = []
    @VState private var selected = 0
    @VState private var working = false
    @VState private var custom = ""
    @VState private var showMore = false
    @VState private var edited = ""
    @VState private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rewrite").font(.title3.bold())
            Text(original).font(.callout).foregroundStyle(.secondary).lineLimit(4)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132))], spacing: 6) {
                ForEach(showMore ? RewriteMode.allCases : RewriteMode.primary) { m in
                    Button { go(m) } label: {
                        Label(m.label, systemImage: m.icon).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .tint(mode == m ? .accentColor : nil)
                    .disabled(working || (!aiAvailable && !m.worksOffline))
                }
            }
            HStack {
                Button(showMore ? "Fewer styles" : "More styles…") { showMore.toggle() }.buttonStyle(.link)
                Spacer()
                if !aiAvailable { Text("Turn on Apple Intelligence for every style").font(.caption).foregroundStyle(.orange) }
            }
            HStack {
                TextField("Or describe it: “make it sound like a thank-you note”", text: $custom)
                    .textFieldStyle(.roundedBorder).onSubmit { go(.improve, custom: custom) }
                Button("Rewrite") { go(.improve, custom: custom) }.disabled(custom.isEmpty || working || !aiAvailable)
            }
            Divider()
            if working {
                HStack { ProgressView().controlSize(.small); Text("Writing on your Mac…").foregroundStyle(.secondary) }
            } else if !versions.isEmpty {
                if versions.count > 1 {
                    Picker("", selection: $selected) {
                        ForEach(versions.indices, id: \.self) { Text("Version \($0 + 1)").tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    .onChange(of: selected) { _, v in edited = versions[v] }
                }
                DiffText(old: original, new: edited).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.07)))
                TextEditor(text: $edited).font(.callout).frame(minHeight: 70, maxHeight: 140)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1)))
                HStack {
                    Text("\(TextUtil.wordCount(original)) → \(TextUtil.wordCount(edited)) words").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Try again") { if let mode { go(mode, custom: custom.isEmpty ? nil : custom) } }
                    Button(copied ? "Copied" : "Copy") { copy(edited); copied = true }
                    Button("Replace") { replace(edited) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            } else if mode != nil {
                Text("No changes needed — this already reads well.").foregroundStyle(.secondary)
            } else {
                Text("Pick a style above. You'll get up to three versions to choose from.").font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(minWidth: 560, minHeight: 480)
        .onExitCommand(perform: close)
    }

    private func go(_ m: RewriteMode, custom: String? = nil) {
        mode = m
        working = true
        versions = []
        copied = false
        Task {
            let v = await Rewriter.versions(of: original, mode: m, custom: custom?.isEmpty == false ? custom : nil)
            versions = v
            selected = 0
            edited = v.first ?? ""
            working = false
        }
    }
}

/// Shows a rewrite with removed words struck through and added words highlighted.
struct DiffText: View {
    let old: String
    let new: String
    var body: some View {
        Text(attributed)
            .font(.callout)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        let a = old.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let b = new.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard a.count * b.count < 200_000 else { return AttributedString(new) }
        var lcs = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var out = AttributedString()
        var i = 0, j = 0
        func add(_ s: String, _ kind: Int) {
            var piece = AttributedString(s + " ")
            if kind < 0 { piece.strikethroughStyle = .single; piece.foregroundColor = .secondary }
            if kind > 0 { piece.backgroundColor = Color.green.opacity(0.25) }
            out += piece
        }
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] { add(b[j], 0); i += 1; j += 1 }
            else if j < b.count, i == a.count || lcs[i][j + 1] >= lcs[i + 1][j] { add(b[j], 1); j += 1 }
            else { add(a[i], -1); i += 1 }
        }
        return out
    }
}
