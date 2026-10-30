// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import AppKit
import SwiftUI

@main
struct JustTypeItApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = Store.shared
    @StateObject private var model = EditorModel()

    var body: some Scene {
        Window("Just Type It", id: "main") {
            MainView(model: model, store: store)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Just Type It") { AppDelegate.showAbout() }
            }
            CommandGroup(after: .newItem) {
                Button("New Document") { NotificationCenter.default.post(name: .newDocument, object: nil) }
                    .keyboardShortcut("n")
                Button("Open…") { NotificationCenter.default.post(name: .openDocument, object: nil) }
                    .keyboardShortcut("o")
                Button("Export…") { NotificationCenter.default.post(name: .exportDocument, object: nil) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            CommandMenu("Check") {
                Button("Run AI Check Now") { Task { await model.runAI() } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Accept All Suggestions") { model.acceptAll() }
                    .keyboardShortcut("a", modifiers: [.command, .option])
            }
        }

        MenuBarExtra("Just Type It", systemImage: "character.cursor.ibeam") {
            MenuBarContent(store: store)
        }

        Settings {
            SettingsView(store: store)
        }
    }
}

extension Notification.Name {
    static let newDocument = Notification.Name("jti.newDocument")
    static let openDocument = Notification.Name("jti.openDocument")
    static let exportDocument = Notification.Name("jti.exportDocument")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ n: Notification) {
        if CommandLine.arguments.contains("--self-test") {
            exit(MainActor.assumeIsolated { SelfTest.run() })
        }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.servicesProvider = ServiceProvider()
        NSUpdateDynamicServices()
        MainActor.assumeIsolated {
            QuickCheck.shared.installHotkey()
            let p = Store.shared.prefs
            if p.checkEverywhere { Everywhere.shared.start() }
            if !p.onboarded { Onboarding.show() }
            LoginItem.set(p.launchAtLogin)
            // Started at login: stay in the menu bar, don't open the window.
            if CommandLine.arguments.contains("--background") || NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: keyAELaunchedAsLogInItem) != nil {
                DispatchQueue.main.async { NSApp.windows.filter { $0.title == "Just Type It" }.forEach { $0.close() } }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppDelegate.openMain() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { Store.shared.saveNow() }
    }

    static func openMain() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { $0.title == "Just Type It" || $0.identifier?.rawValue == "main" }) {
            w.makeKeyAndOrderFront(nil)
        }
    }

    static func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Just Type It",
            .credits: NSAttributedString(string: "Created by Stefano Roman Gunness\nA free, private AI writing assistant for Mac.\nMIT License"),
        ])
    }
}

/// "Check with Just Type It" in every app's Services menu (right-click selected text).
final class ServiceProvider: NSObject {
    @objc func checkText(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let s = pboard.string(forType: .string), !s.isEmpty else { return }
        MainActor.assumeIsolated { QuickCheck.shared.show(text: s, canReplace: false) }
    }
}

struct MenuBarContent: View {
    @ObservedObject var store: Store
    @ObservedObject var everywhere = Everywhere.shared

    var body: some View {
        if everywhere.running {
            if !everywhere.isTrusted {
                Text("⚠️ Allow Accessibility to check other apps")
                Button("Open Accessibility Settings…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            } else {
                if let until = everywhere.pausedUntil { Text("⏸ Paused until \(until.formatted(date: .omitted, time: .shortened))") }
                else { Text("✓ Checking as you type in every app") }
                if !everywhere.currentApp.isEmpty { Text("\(everywhere.currentApp): \(everywhere.issueCount) suggestion\(everywhere.issueCount == 1 ? "" : "s")") }
                if let error = everywhere.editError { Text(error) }
            }
        }
        Toggle("Check in All Apps", isOn: Binding(get: { store.prefs.checkEverywhere }, set: { v in
            store.prefs.checkEverywhere = v
            v ? Everywhere.shared.start() : Everywhere.shared.stop()
        }))
        Toggle("AI Suggestions in All Apps", isOn: $store.prefs.aiEverywhere)
        Menu("Pause Checking") {
            Button("For 1 Hour") { everywhere.pausedUntil = Date().addingTimeInterval(3600) }
            Button("Until Tomorrow") { everywhere.pausedUntil = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400)) }
            if everywhere.pausedUntil != nil { Button("Resume Now") { everywhere.pausedUntil = nil } }
        }
        Menu("English: \(store.prefs.dialect.label.replacingOccurrences(of: " English", with: ""))") {
            ForEach(Dialect.allCases) { d in
                Button { store.prefs.dialect = d } label: { if store.prefs.dialect == d { Label(d.label, systemImage: "checkmark") } else { Text(d.label) } }
            }
        }
        if let app = NSWorkspace.shared.menuBarOwningApplication, let bid = app.bundleIdentifier, bid != Bundle.main.bundleIdentifier {
            Button(store.prefs.excludedApps.contains(bid) ? "Resume in \(app.localizedName ?? bid)" : "Pause in \(app.localizedName ?? bid)") {
                if let i = store.prefs.excludedApps.firstIndex(of: bid) { store.prefs.excludedApps.remove(at: i) } else { store.prefs.excludedApps.append(bid) }
            }
        }
        Divider()
        Button("Open Just Type It") { AppDelegate.openMain() }
        Button("\(store.stats.suggestionsAccepted) fixes accepted so far") { AppDelegate.openMain() }
        Button("Check Selected Text  ⌃⌥G") { QuickCheck.shared.run() }
        Toggle("Launch at Login", isOn: Binding(get: { store.prefs.launchAtLogin }, set: { v in
            store.prefs.launchAtLogin = v
            LoginItem.set(v)
        }))
        Divider()
        Button("About Just Type It") { AppDelegate.showAbout() }
        Button("Quit Just Type It") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
