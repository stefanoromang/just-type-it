// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import Foundation
import ServiceManagement

/// Starts Just Type It when you log in, so checking is always on.
enum LoginItem {
    static func set(_ on: Bool) {
        // Only register from an installed .app bundle, not from `swift run`.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let svc = SMAppService.mainApp
        do {
            if on, svc.status != .enabled { try svc.register() }
            if !on, svc.status == .enabled { try svc.unregister() }
        } catch {
            NSLog("Just Type It: login item change failed: \(error.localizedDescription)")
        }
    }
}
