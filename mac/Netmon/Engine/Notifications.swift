import Foundation
import UserNotifications
import AppKit

extension Notification.Name {
    static let netmonOpenMainWindow = Notification.Name("NetmonOpenMainWindow")
}

/// Posts native Notification Center alerts when outages start or end.
@MainActor
final class NotificationCoord: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoord()

    private let center = UNUserNotificationCenter.current()
    private var authorized = false

    override init() {
        super.init()
        center.delegate = self
    }

    /// Best-effort request for permission. Silently no-ops if the user declines.
    func requestAuthorization() async {
        do {
            authorized = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            authorized = false
        }
    }

    func outageStarted(_ outage: OutageEvent) {
        guard Preferences.shared.notificationsEnabled else { return }
        post(
            id: "start-\(outage.id)",
            title: outage.type == .connectivity ? "Network outage" : "Partial network outage",
            body: bodyForStart(outage)
        )
    }

    func outageEnded(_ outage: OutageEvent) {
        guard Preferences.shared.notificationsEnabled else { return }
        let duration = outage.durationMs.map(formatDuration(ms:)) ?? "unknown duration"
        post(
            id: "end-\(outage.id)",
            title: "Network recovered",
            body: "Outage lasted \(duration)."
        )
    }

    private func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(req)
    }

    private func bodyForStart(_ outage: OutageEvent) -> String {
        let host = "8.8.8.8"
        let loss = String(format: "%.0f%%", outage.startPacketLoss)
        let dns = outage.startDNSFailure ? " · DNS failing" : ""
        return "Can't reach \(host) · \(loss) packet loss\(dns)"
    }

    private func formatDuration(ms: Double) -> String {
        let s = ms / 1000
        if s < 60 { return String(format: "%.0fs", s) }
        if s < 3600 { return String(format: "%dm %ds", Int(s/60), Int(s.truncatingRemainder(dividingBy: 60))) }
        return String(format: "%.1fh", s/3600)
    }

    // MARK: - Notification action: clicking opens Netmon.

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .netmonOpenMainWindow, object: nil)
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
