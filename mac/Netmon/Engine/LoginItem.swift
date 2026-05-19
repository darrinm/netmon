import Foundation
import ServiceManagement

/// Thin wrapper around SMAppService.mainApp for register/unregister at login.
enum LoginItem {
    static var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Sync the OS state to match the desired value. Throws on failure.
    static func setEnabled(_ enabled: Bool) throws {
        let svc = SMAppService.mainApp
        if enabled {
            if svc.status != .enabled {
                try svc.register()
            }
        } else {
            if svc.status == .enabled {
                try svc.unregister()
            }
        }
    }
}
