// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Works in any app: press ⌃⌥G with text selected to check it in a floating panel,
/// then paste the corrected text back.
@MainActor
final class QuickCheck {
    static let shared = QuickCheck()
    private var panel: NSPanel?
    private var sourceApp: NSRunningApplication?
    private var hotKeyRef: EventHotKeyRef?

    func installHotkey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { QuickCheck.shared.run() } }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x4A54_4954), id: 1) // 'JTIT'
        RegisterEventHotKey(UInt32(kVK_ANSI_G), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func run() {
        sourceApp = NSWorkspace.shared.frontmostApplication
        if sourceApp?.bundleIdentifier == Bundle.main.bundleIdentifier { sourceApp = nil }
        Task {
            let text = await copySelection()
            guard let text, !text.isEmpty else {
                show(text: "", canReplace: false, note: "Select some text in any app, then press ⌃⌥G. (Allow Accessibility for Just Type It in System Settings › Privacy & Security if nothing happens.)")
                return
            }
            show(text: text, canReplace: true)
        }
    }

    func show(text: String, canReplace: Bool, note: String? = nil) {
        panel?.close()
        let model = EditorModel()
        model.text = text
        let view = QuickCheckView(model: model, original: text, canReplace: canReplace && sourceApp != nil, note: note) { [weak self] result in
            self?.finish(result)
        }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520), styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .utilityWindow],
                        backing: .buffered, defer: false)
        p.title = "Just Type It – Quick Check"
        p.isFloatingPanel = true
        p.level = .floating
        p.contentView = NSHostingView(rootView: view)
        p.center()
        p.isReleasedWhenClosed = false
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        panel = p
    }

    private func finish(_ result: String?) {
        panel?.close()
        guard let result, let app = sourceApp else { return }
        app.activate()
        Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            let pb = NSPasteboard.general
            let saved = pb.string(forType: .string)
            pb.clearContents()
            pb.setString(result, forType: .string)
            sendKey(CGKeyCode(kVK_ANSI_V))
            try? await Task.sleep(nanoseconds: 400_000_000)
            if let saved { pb.clearContents(); pb.setString(saved, forType: .string) }
        }
    }

    private func copySelection() async -> String? {
        // Accessibility first, then ⌘C as a fallback.
        if AXIsProcessTrusted() {
            let sys = AXUIElementCreateSystemWide()
            var f: CFTypeRef?
            if AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &f) == .success, let f {
                var sel: CFTypeRef?
                if AXUIElementCopyAttributeValue(f as! AXUIElement, kAXSelectedTextAttribute as CFString, &sel) == .success,
                   let s = sel as? String, !s.isEmpty { return s }
            }
        } else {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
        let pb = NSPasteboard.general
        let before = pb.changeCount
        let saved = pb.string(forType: .string)
        sendKey(CGKeyCode(kVK_ANSI_C))
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if pb.changeCount != before { break }
        }
        guard pb.changeCount != before else { return nil }
        let s = pb.string(forType: .string)
        if let saved { pb.clearContents(); pb.setString(saved, forType: .string) }
        return s
    }

    private func sendKey(_ code: CGKeyCode) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let d = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)
        let u = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
        d?.flags = .maskCommand
        u?.flags = .maskCommand
        d?.post(tap: .cghidEventTap)
        u?.post(tap: .cghidEventTap)
    }
}

struct QuickCheckView: View {
    @ObservedObject var model: EditorModel
    let original: String
    let canReplace: Bool
    var note: String?
    let done: (String?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let note {
                Text(note).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    TextEditorView(model: model).frame(minWidth: 380)
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            if model.issues.isEmpty {
                                Label("Looks great!", systemImage: "checkmark.seal.fill").foregroundStyle(.green).padding(.top, 30)
                            }
                            ForEach(model.issues) { IssueCard(issue: $0, model: model) }
                        }.padding(12)
                    }.frame(minWidth: 280, maxWidth: 340)
                }
            }
            Divider()
            HStack {
                Text("Score \(model.metrics.overall)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                if model.aiChecking { ProgressView().controlSize(.small); Text("AI checking…").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Fix all") { model.acceptAll() }.disabled(model.issues.isEmpty)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.text, forType: .string)
                }
                Button("Cancel") { done(nil) }.keyboardShortcut(.cancelAction)
                if canReplace {
                    Button("Replace in app") { done(model.text) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                }
            }.padding(12)
        }
        .onAppear { if note == nil { model.recheck(immediate: true) } }
    }
}
