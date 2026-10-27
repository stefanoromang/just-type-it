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
            Button("Open Just Type It") { AppDelegate.openMain() }
            Button("Check Selected Text in Any App  ⌃⌥G") { QuickCheck.shared.run() }
            Divider()
            Button("About Just Type It") { AppDelegate.showAbout() }
            Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
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
        MainActor.assumeIsolated { QuickCheck.shared.installHotkey() }
    }

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
