// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import AppKit
import SwiftUI

/// First-run setup: explains always-on checking and walks through the Accessibility permission.
@MainActor
enum Onboarding {
    private static var window: NSWindow?

    static func show() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.title = "Welcome to Just Type It"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: OnboardingView { w.close(); Store.shared.prefs.onboarded = true })
        w.center()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        window = w
    }
}

struct OnboardingView: View {
    let done: () -> Void
    @VState private var trusted = AXIsProcessTrusted()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
            Text("Just Type It checks your writing everywhere").font(.title2.bold()).multilineTextAlignment(.center)
            Text("Type in Outlook, Mail, Gmail, Word, Slack, Teams, Notes or any other app. Mistakes are underlined as you type, and you can fix each one with a click.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 440)
            VStack(alignment: .leading, spacing: 12) {
                step(1, "Allow Accessibility", trusted ? "Done. Just Type It can read and fix text in other apps." : "Needed to see the text box you're typing in. Your text never leaves your Mac.", done: trusted) {
                    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(opts)
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                step(2, "Start typing anywhere", "Click an underline for the fix. The colored badge in the corner of the text box lists every suggestion, with Fix all.", done: false, action: nil)
                step(3, "Turn on Apple Intelligence (optional)", AIEngine.available ? "On. AI suggestions, rewrites and agents are ready." : "System Settings › Apple Intelligence & Siri. It adds AI suggestions, rewrites and tone changes.", done: AIEngine.available, action: AIEngine.available ? nil : {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!)
                })
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
            Text("Just Type It lives in your menu bar (the cursor icon) and starts when you log in.").font(.caption).foregroundStyle(.secondary)
            Button(trusted ? "Get started" : "Continue without other apps", action: done).buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(28)
        .frame(width: 560)
        .onReceive(timer) { _ in
            let now = AXIsProcessTrusted()
            if now != trusted {
                trusted = now
                if now, Store.shared.prefs.checkEverywhere { Everywhere.shared.stop(); Everywhere.shared.start() }
            }
        }
    }

    private func step(_ n: Int, _ title: String, _ detail: String, done: Bool, action: (() -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.accentColor.opacity(0.15)).frame(width: 26, height: 26)
                if done { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } else { Text("\(n)").font(.caption.bold()) }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let action, !done { Button("Open", action: action) }
        }
    }
}
