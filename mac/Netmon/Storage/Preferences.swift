import Foundation
import Observation

/// Lightweight @Observable wrapper around UserDefaults. Bound to SettingsView
/// and pushed into MonitorEngine + Notifications on change.
@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    enum Key {
        static let pingHost = "pingHost"
        static let dnsHost = "dnsHost"
        static let intervalSeconds = "intervalSeconds"
        static let notificationsEnabled = "notificationsEnabled"
        static let launchAtLogin = "launchAtLogin"
    }

    var pingHost: String {
        didSet { defaults.set(pingHost, forKey: Key.pingHost) }
    }

    var dnsHost: String {
        didSet { defaults.set(dnsHost, forKey: Key.dnsHost) }
    }

    var intervalSeconds: Int {
        didSet { defaults.set(intervalSeconds, forKey: Key.intervalSeconds) }
    }

    var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) }
    }

    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    private init() {
        defaults.register(defaults: [
            Key.pingHost: "8.8.8.8",
            Key.dnsHost: "google.com",
            Key.intervalSeconds: 30,
            Key.notificationsEnabled: true,
            Key.launchAtLogin: false,
        ])
        pingHost = defaults.string(forKey: Key.pingHost) ?? "8.8.8.8"
        dnsHost = defaults.string(forKey: Key.dnsHost) ?? "google.com"
        intervalSeconds = defaults.integer(forKey: Key.intervalSeconds)
        notificationsEnabled = defaults.bool(forKey: Key.notificationsEnabled)
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
    }
}
